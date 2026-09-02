import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Filter: String, CaseIterable, Identifiable {
        case all, onDisk, relocated
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Toutes"
            case .onDisk: return "Sur le disque"
            case .relocated: return "Déplacées"
            }
        }
    }

    private enum Keys {
        static let destination = "destinationPath"
        static let createAppSymlink = "createAppSymlink"
    }

    // Scan results
    private(set) var apps: [InstalledApp] = []
    private(set) var records: [MoveRecord] = []
    private(set) var bundleSizes: [String: Int64] = [:]
    private(set) var isScanning = false

    // Selection
    var selectedRowID: AppRow.ID?
    var searchText = ""
    var filter: Filter = .all

    // Support files of the selected app
    private(set) var supportItems: [SupportItem] = []
    var selectedSupportIDs: Set<String> = []
    private(set) var isLoadingSupport = false
    private var supportItemsAppID: String?

    // Running operation
    private(set) var isBusy = false
    private(set) var operationLabel = ""
    private(set) var operationProgress: Double = 0

    // Presentation
    var errorMessage: String?
    var showSettings = false

    // Preferences
    var destinationPath: String {
        didSet { UserDefaults.standard.set(destinationPath, forKey: Keys.destination) }
    }
    var createAppSymlink: Bool {
        didSet { UserDefaults.standard.set(createAppSymlink, forKey: Keys.createAppSymlink) }
    }

    private let ledger = Ledger()

    init() {
        let defaults = UserDefaults.standard
        destinationPath = defaults.string(forKey: Keys.destination) ?? ""
        createAppSymlink = defaults.object(forKey: Keys.createAppSymlink) as? Bool ?? true
    }

    // MARK: - Derived state

    var rows: [AppRow] {
        var result = apps.map { app in
            AppRow(id: app.id,
                   name: app.name,
                   app: app,
                   record: ledger.record(forAppNamed: app.name),
                   size: ledger.record(forAppNamed: app.name)?.totalBytes ?? bundleSizes[app.id])
        }
        let present = Set(apps.map(\.name))
        for record in records where !present.contains(record.appName) {
            result.append(AppRow(id: record.destinationRoot,
                                 name: record.appName,
                                 app: nil,
                                 record: record,
                                 size: record.totalBytes))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var visibleRows: [AppRow] {
        rows.filter { row in
            switch filter {
            case .all: return true
            case .onDisk: return !row.isRelocated
            case .relocated: return row.isRelocated
            }
        }
        .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var selectedRow: AppRow? {
        guard let selectedRowID else { return nil }
        return rows.first { $0.id == selectedRowID }
    }

    var totalReclaimed: Int64 {
        records.reduce(0) { $0 + $1.totalBytes }
    }

    var selectedSupportBytes: Int64 {
        supportItems.filter { selectedSupportIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    // MARK: - Scanning

    func refresh() {
        isScanning = true
        records = ledger.records
        let scanned = AppScanner.scan()
        apps = scanned
        isScanning = false

        Task.detached(priority: .utility) { [weak self] in
            for app in scanned {
                let size = FileSize.onDisk(of: app.installedURL)
                await MainActor.run { self?.bundleSizes[app.id] = size }
            }
        }
    }

    func loadSupportItems(for row: AppRow) {
        guard let app = row.app, !row.isRelocated else {
            supportItems = []
            selectedSupportIDs = []
            supportItemsAppID = nil
            return
        }
        guard supportItemsAppID != app.id else { return }

        supportItemsAppID = app.id
        supportItems = []
        selectedSupportIDs = []
        isLoadingSupport = true

        Task.detached(priority: .userInitiated) { [weak self] in
            let items = SupportFileLocator.locate(app: app)
            await MainActor.run {
                guard let self, self.supportItemsAppID == app.id else { return }
                self.supportItems = items
                self.selectedSupportIDs = Set(items.map(\.id))
                self.isLoadingSupport = false
            }
        }
    }

    func toggleSupportItem(_ item: SupportItem) {
        if selectedSupportIDs.contains(item.id) {
            selectedSupportIDs.remove(item.id)
        } else {
            selectedSupportIDs.insert(item.id)
        }
    }

    // MARK: - Actions

    func relocateSelected() {
        guard let row = selectedRow, let app = row.app, !row.isRelocated else { return }
        guard !destinationPath.isEmpty else {
            errorMessage = RelocationError.noDestination.localizedDescription
            showSettings = true
            return
        }

        let destination = URL(fileURLWithPath: destinationPath)
        let chosen = supportItems.filter { selectedSupportIDs.contains($0.id) }

        do {
            let plan = try Relocator.planRelocation(app: app,
                                                    supportItems: chosen,
                                                    destination: destination,
                                                    createAppSymlink: createAppSymlink)
            perform(plan.operations) { [self] in
                Relocator.writeManifest(plan.record)
                ledger.add(plan.record)
                supportItemsAppID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreSelected() {
        guard let row = selectedRow, let record = row.record else { return }
        do {
            let operations = try Relocator.planRestore(record: record)
            perform(operations) { [self] in
                Relocator.pruneEmptyDirectories(at: record.destinationRootURL)
                ledger.remove(appNamed: record.appName)
                supportItemsAppID = nil
                selectedRowID = record.bundleItem?.originalPath
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ operations: [FileOperation], onSuccess: @escaping @MainActor () -> Void) {
        isBusy = true
        operationProgress = 0
        operationLabel = "Préparation…"

        Task.detached(priority: .userInitiated) { [weak self] in
            var failure: Error?
            do {
                try FileOperation.execute(operations) { label, fraction in
                    Task { @MainActor in
                        self?.operationLabel = label
                        self?.operationProgress = fraction
                    }
                }
            } catch {
                failure = error
            }

            await MainActor.run {
                guard let self else { return }
                if let failure {
                    self.errorMessage = failure.localizedDescription
                } else {
                    onSuccess()
                }
                self.isBusy = false
                self.refresh()
            }
        }
    }
}
