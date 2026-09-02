import Foundation

enum RelocationError: LocalizedError {
    case noDestination
    case destinationUnusable(String)
    case destinationForbidden(String)
    case alreadyRelocated(String)
    case targetExists(String)
    case missingSource(String)
    case originalOccupied(String)

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
        for forbidden in ["/Applications", "/System", "/Library"] where
            destinationPath == forbidden || destinationPath.hasPrefix(forbidden + "/") {
            throw RelocationError.destinationForbidden(destinationPath)
        }
        guard !app.isRelocated else { throw RelocationError.alreadyRelocated(app.name) }
        guard fm.fileExists(atPath: app.installedURL.path) else {
            throw RelocationError.missingSource(app.installedURL.path)
        }

        let root = destination.appendingPathComponent(app.name)
        let bundleTarget = root.appendingPathComponent(app.installedURL.lastPathComponent)
        guard !fm.fileExists(atPath: bundleTarget.path) else {
            throw RelocationError.targetExists(bundleTarget.path)
        }

        var operations: [FileOperation] = [.makeDirectory(root)]
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

        let supportRoot = root.appendingPathComponent("Support")
        for item in supportItems {
            let directory = supportRoot.appendingPathComponent(item.kind.librarySubpath)
            let target = directory.appendingPathComponent(item.url.lastPathComponent)
            guard fm.fileExists(atPath: item.url.path) else {
                throw RelocationError.missingSource(item.url.path)
            }
            guard !fm.fileExists(atPath: target.path) else {
                throw RelocationError.targetExists(target.path)
            }
            operations.append(.makeDirectory(directory))
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
                                destinationRoot: root.path,
                                movedAt: Date(),
                                items: items)
        return (operations, record)
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

    /// Best-effort tidy-up of the now-empty <destination>/<AppName> folder.
    static func pruneEmptyDirectories(at root: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: root.appendingPathComponent(manifestName))

        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [],
                                             errorHandler: { _, _ in true }) else { return }
        let directories = enumerator.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.pathComponents.count > $1.pathComponents.count }

        for directory in directories + [root] {
            if let contents = try? fm.contentsOfDirectory(atPath: directory.path), contents.isEmpty {
                try? fm.removeItem(at: directory)
            }
        }
    }

    // MARK: - Manifest

    static let manifestName = ".macintoshhd-manifest.json"

    /// Drops a copy of the record next to the moved files so the move stays
    /// readable even if the ledger is lost. Best effort only.
    static func writeManifest(_ record: MoveRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: record.destinationRootURL.appendingPathComponent(manifestName))
    }
}
