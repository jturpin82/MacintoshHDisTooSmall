import Foundation

enum RelocationError: LocalizedError {
    case noDestination
    case destinationUnusable(String)
    case destinationForbidden(String)
    case alreadyRelocated(String)
    case targetExists(String)
    case missingSource(String)
    case originalOccupied(String)
    case trashUnavailable(String)
    case notRelocated(String)
    case privilegedRetryFailed(privileged: String, original: String)

    var errorDescription: String? {
        switch self {
        case .noDestination:
            return "Aucun dossier de destination n'est configuré. Ouvre les réglages pour en choisir un."
        case .destinationUnusable(let path):
            return "Le dossier de destination est introuvable : \(path)"
        case .destinationForbidden(let path):
            return "Destination refusée : \(path). Choisis un dossier en dehors de /Applications et /System."
        case .alreadyRelocated(let name):
            return "\(name) est déjà un lien symbolique : l'app a déjà été déplacée."
        case .targetExists(let path):
            return "La destination existe déjà : \(path). Supprime-la ou restaure d'abord l'app."
        case .missingSource(let path):
            return "Introuvable : \(path)"
        case .originalOccupied(let path):
            return "Un vrai fichier occupe l'emplacement d'origine : \(path). L'app a probablement été réinstallée."
        case .trashUnavailable(let path):
            return "Ce volume n'a pas de corbeille (exFAT, NTFS…), impossible d'y mettre \(path)."
        case .notRelocated(let name):
            return "\(name) n'est pas un lien symbolique dans /Applications : rien à considérer comme déplacé."
        case .privilegedRetryFailed(let privileged, let original):
            return """
            \(privileged)

            Échec initial, sans privilèges : \(original)
            """
        }
    }
}

enum Relocator {

    // MARK: - Moving out

    static func planRelocation(app: InstalledApp,
                               supportItems: [SupportItem],
                               destination: URL,
                               createAppSymlink: Bool) throws -> (operations: [FileOperation], record: MoveRecord) {
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RelocationError.destinationUnusable(destination.path)
        }
        let destinationPath = destination.standardizedFileURL.path
        let forbiddenRoots = ["/Applications", "/System", "/Library"]
        if forbiddenRoots.contains(where: { destinationPath == $0 || destinationPath.hasPrefix($0 + "/") }) {
            throw RelocationError.destinationForbidden(destinationPath)
        }
        guard !app.isRelocated else { throw RelocationError.alreadyRelocated(app.name) }
        guard fm.fileExists(atPath: app.installedURL.path) else {
            throw RelocationError.missingSource(app.installedURL.path)
        }

        // Every app moved to the same destination shares these top-level
        // folders, mirroring /Applications and ~/Library one level down
        // rather than nesting everything under a per-app directory.
        let appsFolder = destination.appendingPathComponent("Applications")
        let bundleTarget = appsFolder.appendingPathComponent(app.installedURL.lastPathComponent)
        guard !fm.fileExists(atPath: bundleTarget.path) else {
            throw RelocationError.targetExists(bundleTarget.path)
        }

        var operations: [FileOperation] = [.makeDirectory(appsFolder)]
        var items: [MovedItem] = []

        let bundleSize = FileSize.onDisk(of: app.installedURL)
        operations.append(.move(from: app.installedURL, to: bundleTarget))
        if createAppSymlink {
            operations.append(.makeSymlink(link: app.installedURL, target: bundleTarget))
        }
        items.append(MovedItem(kind: MovedItem.bundleKind,
                               originalPath: app.installedURL.path,
                               relocatedPath: bundleTarget.path,
                               symlinkCreated: createAppSymlink,
                               bytes: bundleSize))

        for item in supportItems {
            let folder = destination.appendingPathComponent(item.kind.destinationFolderName)
            let target = folder.appendingPathComponent(item.url.lastPathComponent)
            guard fm.fileExists(atPath: item.url.path) else {
                throw RelocationError.missingSource(item.url.path)
            }
            guard !fm.fileExists(atPath: target.path) else {
                throw RelocationError.targetExists(target.path)
            }
            operations.append(.makeDirectory(folder))
            operations.append(.move(from: item.url, to: target))
            // Support files are always symlinked back, otherwise the app just
            // recreates them and nothing is reclaimed.
            operations.append(.makeSymlink(link: item.url, target: target))
            items.append(MovedItem(kind: item.kind.rawValue,
                                   originalPath: item.url.path,
                                   relocatedPath: target.path,
                                   symlinkCreated: true,
                                   bytes: item.size))
        }

        let record = MoveRecord(appName: app.name,
                                bundleID: app.bundleID,
                                destinationRoot: destination.standardizedFileURL.path,
                                movedAt: Date(),
                                items: items)
        return (operations, record)
    }

    // MARK: - Adopting

    /// Folds an app that was relocated by some other means into the ledger,
    /// without moving a single file: it is already out of /Applications, this
    /// only starts tracking it so restore/delete/"oublier" work on it too.
    static func planAdoption(app: InstalledApp, adopting supportItems: [AdoptableItem]) throws -> MoveRecord {
        guard app.isRelocated else { throw RelocationError.notRelocated(app.name) }
        let resolvedBundle = app.installedURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolvedBundle.path) else {
            throw RelocationError.missingSource(app.installedURL.path)
        }

        var items = [MovedItem(kind: MovedItem.bundleKind,
                               originalPath: app.installedURL.path,
                               relocatedPath: resolvedBundle.path,
                               symlinkCreated: true,
                               bytes: FileSize.onDisk(of: resolvedBundle))]

        items += supportItems.map {
            MovedItem(kind: $0.kind.rawValue,
                     originalPath: $0.originalURL.path,
                     relocatedPath: $0.resolvedURL.path,
                     symlinkCreated: true,
                     bytes: $0.size)
        }

        return MoveRecord(appName: app.name,
                          bundleID: app.bundleID,
                          destinationRoot: resolvedBundle.deletingLastPathComponent().path,
                          movedAt: Date(),
                          items: items)
    }

    // MARK: - Moving back

    static func planRestore(record: MoveRecord) throws -> [FileOperation] {
        let fm = FileManager.default
        var operations: [FileOperation] = []

        for item in record.items {
            guard fm.fileExists(atPath: item.relocatedPath) else {
                throw RelocationError.missingSource(item.relocatedPath)
            }
            let original = item.originalURL
            let isSymlink = (try? original.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
            if isSymlink {
                operations.append(.removeSymlink(original))
            } else if fm.fileExists(atPath: original.path) {
                throw RelocationError.originalOccupied(original.path)
            }
            operations.append(.makeDirectory(original.deletingLastPathComponent()))
            operations.append(.move(from: item.relocatedURL, to: original))
        }

        return operations
    }

    /// Best-effort tidy-up after a restore: this app's manifest, then any
    /// directory left empty by the items that just moved back. `root` — the
    /// destination folder the user configured — is deliberately never removed
    /// itself, since several apps can share it (Applications, ApplicationSupport,
    /// Caches… hold every app moved to that destination, not just this one).
    static func pruneEmptyDirectories(after record: MoveRecord) {
        let fm = FileManager.default
        let root = record.destinationRootURL

        try? fm.removeItem(at: manifestURL(for: record))
        // Apps relocated before 0.2.2 wrote a flat manifest name directly at
        // their (then per-app-exclusive) root; drop it too if still there.
        try? fm.removeItem(at: root.appendingPathComponent(legacyManifestName))
        let metadataDir = root.appendingPathComponent(metadataFolderName)
        if let contents = try? fm.contentsOfDirectory(atPath: metadataDir.path), contents.isEmpty {
            try? fm.removeItem(at: metadataDir)
        }

        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [],
                                             errorHandler: { _, _ in true }) else { return }
        let directories = enumerator.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.pathComponents.count > $1.pathComponents.count }

        for directory in directories {
            if let contents = try? fm.contentsOfDirectory(atPath: directory.path), contents.isEmpty {
                try? fm.removeItem(at: directory)
            }
        }
    }

    // MARK: - Deleting

    /// Sends an app still living in /Applications, plus the support items the
    /// user ticked, to the Trash.
    static func planDeletion(app: InstalledApp, supportItems: [SupportItem]) throws -> [FileOperation] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: app.installedURL.path) else {
            throw RelocationError.missingSource(app.installedURL.path)
        }
        var operations: [FileOperation] = [.trash(app.installedURL)]
        for item in supportItems where fm.fileExists(atPath: item.url.path) {
            operations.append(.trash(item.url))
        }
        return operations
    }

    /// Sends a relocated app to the Trash: the links left behind go first, then
    /// each moved item individually — never the shared destination folder as a
    /// whole, since other apps moved to the same destination live in it too.
    static func planDeletion(record: MoveRecord) throws -> [FileOperation] {
        let fm = FileManager.default
        var operations: [FileOperation] = []

        for item in record.items where item.symlinkCreated {
            let original = item.originalURL
            // Never touch a real bundle: the app may have been reinstalled since.
            if (try? original.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                operations.append(.removeSymlink(original))
            }
        }

        let trashed = record.items.filter { fm.fileExists(atPath: $0.relocatedPath) }
        operations.append(contentsOf: trashed.map { .trash($0.relocatedURL) })

        guard !trashed.isEmpty else { throw RelocationError.missingSource(record.destinationRoot) }
        return operations
    }

    // MARK: - Manifest

    private static let metadataFolderName = ".macintoshhd"
    private static let legacyManifestName = ".macintoshhd-manifest.json"

    /// Where the read-only manifest for one app's relocation is written, kept
    /// outside the moved content and namespaced per app: several apps now
    /// share the same top-level Applications / ApplicationSupport / Caches
    /// folders under one destination, so they can't all write the same file.
    private static func manifestURL(for record: MoveRecord) -> URL {
        let safeName = record.appName.replacingOccurrences(of: "/", with: "-")
        return record.destinationRootURL
            .appendingPathComponent(metadataFolderName)
            .appendingPathComponent("\(safeName).json")
    }

    /// Drops a copy of the record next to the moved files so the move stays
    /// readable even if the ledger is lost. Best effort only.
    static func writeManifest(_ record: MoveRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return }
        let url = manifestURL(for: record)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}
