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

    enum SortOrder: String, CaseIterable, Identifiable {
        case nameAscending, nameDescending, sizeDescending, sizeAscending
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nameAscending: return "Nom (A → Z)"
            case .nameDescending: return "Nom (Z → A)"
            case .sizeDescending: return "Taille (décroissante)"
            case .sizeAscending: return "Taille (croissante)"
            }
        }
    }

    private enum Keys {
        static let destination = "destinationPath"
        static let createAppSymlink = "createAppSymlink"
        static let sortOrder = "sortOrder"
    }

    // Scan results
    private(set) var apps: [InstalledApp] = []
    private(set) var records: [MoveRecord] = []
    private(set) var bundleSizes: [String: Int64] = [:]
    private(set) var supportSizes: [String: Int64] = [:]
    private(set) var isScanning = false
    /// Support items found by the background pass, reused when an app is selected.
    private var supportCache: [String: [SupportItem]] = [:]
    private var sizingTask: Task<Void, Never>?

    // Selection
    var selectedRowID: AppRow.ID?
    var searchText = ""
    var filter: Filter = .all
    var sortOrder: SortOrder = .nameAscending {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }

    // Support files of the selected app
    private(set) var supportItems: [SupportItem] = []
    var selectedSupportIDs: Set<String> = []
    private(set) var isLoadingSupport = false
    private var supportItemsAppID: String?

    // ~/Library items already symlinked elsewhere, for an orphaned selection
    private(set) var adoptableItems: [AdoptableItem] = []
    var selectedAdoptableIDs: Set<String> = []
    private(set) var isLoadingAdoptable = false
    private var adoptableItemsAppID: String?

    // Running operation
    private(set) var isBusy = false
    private(set) var operationLabel = ""
    private(set) var operationProgress: Double = 0

    // Presentation
    var errorMessage: String?
    var showSettings = false
    var showDeleteConfirmation = false
    var showForgetConfirmation = false

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
        sortOrder = defaults.string(forKey: Keys.sortOrder)
            .flatMap(SortOrder.init(rawValue:)) ?? .nameAscending
    }

    // MARK: - Derived state

    var rows: [AppRow] {
        var result = apps.map { app in
            let record = ledger.record(forAppNamed: app.name)
            return AppRow(id: app.id,
                          name: app.name,
                          app: app,
                          record: record,
                          bundleSize: record?.bundleItem?.bytes ?? bundleSizes[app.id],
                          supportSize: record.map { $0.totalBytes - ($0.bundleItem?.bytes ?? 0) }
                              ?? supportSizes[app.id])
        }
        let present = Set(apps.map(\.name))
        for record in records where !present.contains(record.appName) {
            // `record.id` (the app name), not destinationRoot: several apps can
            // share the same destination, and the row id must stay unique.
            result.append(AppRow(id: record.id,
                                 name: record.appName,
                                 app: nil,
                                 record: record,
                                 bundleSize: record.bundleItem?.bytes,
                                 supportSize: record.totalBytes - (record.bundleItem?.bytes ?? 0)))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var visibleRows: [AppRow] {
        let filtered = rows.filter { row in
            switch filter {
            case .all: return true
            case .onDisk: return !row.isRelocated
            case .relocated: return row.isRelocated
            }
        }
        .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }

        switch sortOrder {
        case .nameAscending:
            return filtered
        case .nameDescending:
            return filtered.reversed()
        case .sizeDescending:
            return filtered.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .sizeAscending:
            return filtered.sorted { ($0.size ?? 0) < ($1.size ?? 0) }
        }
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

    /// What a deletion is about to send to the Trash, for the confirmation dialog.
    var deletionSummary: (name: String, itemCount: Int, bytes: Int64)? {
        guard let row = selectedRow else { return nil }
        if let record = row.record {
            return (row.name, record.items.count, record.totalBytes)
        }
        let chosen = supportItems.filter { selectedSupportIDs.contains($0.id) }
        // row.bundleSize follows the symlink for an orphan (so the header
        // shows what the app really weighs), but deleting one — without
        // adopting it first — only trashes that symlink: a few bytes, not
        // the bundle it points to, which stays untouched elsewhere.
        let bundleBytes = row.isOrphaned ? 0 : (row.bundleSize ?? 0)
        return (row.name, chosen.count + 1, bundleBytes + selectedSupportBytes)
    }

    // MARK: - Scanning

    func refresh() {
        isScanning = true
        records = ledger.records
        let scanned = AppScanner.scan()
        apps = scanned
        isScanning = false

        // Sizing walks the whole bundle and every support directory, so it runs
        // in the background and publishes results app by app. A refresh mid-pass
        // cancels the previous one rather than stacking a second full walk.
        sizingTask?.cancel()
        sizingTask = Task.detached(priority: .utility) { [self] in
            for app in scanned {
                if Task.isCancelled { return }
                // FileSize.onDisk deliberately reports 0 for a symlink — right
                // for a tracked app (its real size lives in the ledger record
                // instead), but an orphan has no record yet, so its header
                // would read "0 octet" unless the size follows the link here.
                let bundleSize = app.isRelocated
                    ? FileSize.onDisk(of: app.installedURL.resolvingSymlinksInPath())
                    : FileSize.onDisk(of: app.installedURL)
                // Likewise, `locate` only ever finds items still on this disk —
                // useless for an orphan, whose support files are themselves
                // already symlinks elsewhere; look among those instead.
                let supportSize: Int64
                let itemsToCache: [SupportItem]?
                if app.isRelocated {
                    supportSize = SupportFileLocator.locateAdoptable(app: app).reduce(0) { $0 + $1.size }
                    itemsToCache = nil
                } else {
                    let items = SupportFileLocator.locate(app: app)
                    supportSize = items.reduce(0) { $0 + $1.size }
                    itemsToCache = items
                }
                if Task.isCancelled { return }
                await MainActor.run {
                    self.bundleSizes[app.id] = bundleSize
                    self.supportSizes[app.id] = supportSize
                    if let itemsToCache { self.supportCache[app.id] = itemsToCache }
                }
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

        if let cached = supportCache[app.id] {
            supportItems = cached
            selectedSupportIDs = Set(cached.map(\.id))
            isLoadingSupport = false
            return
        }

        supportItems = []
        selectedSupportIDs = []
        isLoadingSupport = true

        Task.detached(priority: .userInitiated) { [self] in
            let items = SupportFileLocator.locate(app: app)
            await MainActor.run {
                guard self.supportItemsAppID == app.id else { return }
                self.supportItems = items
                self.selectedSupportIDs = Set(items.map(\.id))
                self.supportCache[app.id] = items
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

    func loadAdoptableItems(for row: AppRow) {
        guard let app = row.app, row.isOrphaned else {
            adoptableItems = []
            selectedAdoptableIDs = []
            adoptableItemsAppID = nil
            return
        }
        guard adoptableItemsAppID != app.id else { return }

        adoptableItemsAppID = app.id
        adoptableItems = []
        selectedAdoptableIDs = []
        isLoadingAdoptable = true

        Task.detached(priority: .userInitiated) { [self] in
            let items = SupportFileLocator.locateAdoptable(app: app)
            await MainActor.run {
                guard self.adoptableItemsAppID == app.id else { return }
                self.adoptableItems = items
                self.selectedAdoptableIDs = Set(items.map(\.id))
                self.isLoadingAdoptable = false
            }
        }
    }

    func toggleAdoptableItem(_ item: AdoptableItem) {
        if selectedAdoptableIDs.contains(item.id) {
            selectedAdoptableIDs.remove(item.id)
        } else {
            selectedAdoptableIDs.insert(item.id)
        }
    }

    // MARK: - Actions

    /// Destination proposed by default for a move: the configured one, if any.
    var defaultDestination: URL? {
        destinationPath.isEmpty ? nil : URL(fileURLWithPath: destinationPath)
    }

    /// Moves the selected app. `destination` overrides the configured default
    /// for this move only.
    func relocateSelected(to destination: URL?) {
        guard let row = selectedRow, let app = row.app, !row.isRelocated else { return }
        guard let destination = destination ?? defaultDestination else {
            errorMessage = RelocationError.noDestination.localizedDescription
            showSettings = true
            return
        }

        let chosen = supportItems.filter { selectedSupportIDs.contains($0.id) }

        do {
            let plan = try Relocator.planRelocation(app: app,
                                                    supportItems: chosen,
                                                    destination: destination,
                                                    createAppSymlink: createAppSymlink)
            perform(plan.operations) { [self] in
                Relocator.writeManifest(plan.record)
                ledger.add(plan.record)
                forgetSupportCache(for: app.id)
                if !createAppSymlink {
                    selectedRowID = plan.record.id
                }
            } onFailure: { [self] in
                // Keep whatever actually made it across so it stays restorable.
                reconcile(plan.record)
                forgetSupportCache(for: app.id)
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
                Relocator.pruneEmptyDirectories(after: record)
                ledger.remove(appNamed: record.appName)
                forgetSupportCache(for: record.bundleItem?.originalPath)
                selectedRowID = record.bundleItem?.originalPath
            } onFailure: { [self] in
                // Items already back home must drop out of the record.
                reconcile(record)
                forgetSupportCache(for: record.bundleItem?.originalPath)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sends the selected app and its ticked support items to the Trash.
    func deleteSelected() {
        guard let row = selectedRow else { return }
        do {
            let operations: [FileOperation]
            if let record = row.record {
                operations = try Relocator.planDeletion(record: record)
            } else if let app = row.app {
                let chosen = supportItems.filter { selectedSupportIDs.contains($0.id) }
                operations = try Relocator.planDeletion(app: app, supportItems: chosen)
            } else {
                return
            }

            let appName = row.record?.appName
            perform(operations) { [self] in
                if let appName { ledger.remove(appNamed: appName) }
                forgetSupportCache(for: row.app?.id)
                selectedRowID = nil
            } onFailure: { [self] in
                // A partial deletion leaves the ledger describing files that are gone.
                if let record = row.record { reconcile(record) }
                forgetSupportCache(for: row.app?.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Folds an already-relocated-elsewhere app into the ledger, as-is: no
    /// file is touched, only its record is created. The counterpart to
    /// "Oublier cette entrée" for the opposite problem — an app moved by some
    /// other means, or a lost ledger entry.
    func adoptSelected() {
        guard let row = selectedRow, let app = row.app, row.isOrphaned else { return }
        let chosen = adoptableItems.filter { selectedAdoptableIDs.contains($0.id) }
        do {
            let record = try Relocator.planAdoption(app: app, adopting: chosen)
            Relocator.writeManifest(record)
            ledger.add(record)
            adoptableItemsAppID = nil
            forgetSupportCache(for: app.id)
            // Unlike a move, adoption never touches /Applications: the app is
            // still found there by the scan, so the row keeps app.id as its
            // id (see `rows`) — selectedRowID needs no change.
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Drops a ledger entry without touching a single file. The escape hatch for
    /// an entry that no longer describes reality — an app moved back by hand, or
    /// a move that left the record inconsistent.
    func forgetSelectedRecord() {
        guard let row = selectedRow, let record = row.record else { return }
        ledger.remove(appNamed: record.appName)
        forgetSupportCache(for: row.app?.id)
        selectedRowID = row.app?.id
        refresh()
    }

    private func forgetSupportCache(for appID: String?) {
        supportItemsAppID = nil
        guard let appID else { return }
        supportCache[appID] = nil
        supportSizes[appID] = nil
    }

    /// Rewrites the ledger entry to hold only the items that genuinely moved, so
    /// a half-finished operation stays reversible.
    ///
    /// A file sitting at the relocated path is not proof on its own: a failed
    /// cross-volume move leaves a partial copy there while the original is still
    /// in place. An item only counts as moved once its original slot is empty or
    /// holds the symlink we put there.
    private func reconcile(_ record: MoveRecord) {
        let fm = FileManager.default
        var pruned = record
        pruned.items = record.items.filter { item in
            guard fm.fileExists(atPath: item.relocatedPath) else { return false }
            let original = item.originalURL
            if (try? original.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                return true
            }
            return !fm.fileExists(atPath: original.path)
        }
        if pruned.items.isEmpty {
            ledger.remove(appNamed: record.appName)
        } else {
            ledger.add(pruned)
        }
    }

    private func perform(_ operations: [FileOperation],
                         onSuccess: @escaping @MainActor () -> Void,
                         onFailure: @escaping @MainActor () -> Void) {
        isBusy = true
        operationProgress = 0
        operationLabel = "Préparation…"

        Task.detached(priority: .userInitiated) { [self] in
            let failure: Error?
            do {
                try FileOperation.execute(operations) { label, fraction in
                    Task { @MainActor in
                        self.operationLabel = label
                        self.operationProgress = fraction
                    }
                }
                failure = nil
            } catch {
                failure = error
            }

            await MainActor.run {
                if let failure {
                    onFailure()
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
