import Foundation

enum SupportFileLocator {
    /// Candidate directory names for a given kind, most specific first.
    private static func candidateNames(for kind: SupportItem.Kind, app: InstalledApp) -> [String] {
        var stems: [String] = []
        if let bundleID = app.bundleID, !bundleID.isEmpty { stems.append(bundleID) }
        stems.append(app.name)

        switch kind {
        case .savedState:
            return stems.map { "\($0).savedState" }
        case .httpStorages:
            return stems + stems.map { "\($0).binarycookies" }
        case .containers:
            // Sandbox containers are always keyed by bundle identifier.
            return app.bundleID.map { [$0] } ?? []
        default:
            return stems
        }
    }

    /// Finds cache / configuration items belonging to `app` under ~/Library.
    /// Matching is on exact directory names only — never fuzzy — and the user
    /// confirms the list before anything is moved.
    static func locate(app: InstalledApp) -> [SupportItem] {
        let fm = FileManager.default
        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        var found: [SupportItem] = []
        var seen = Set<String>()

        for kind in SupportItem.Kind.allCases {
            let base = library.appendingPathComponent(kind.librarySubpath)
            for name in candidateNames(for: kind, app: app) {
                let url = base.appendingPathComponent(name)
                guard !seen.contains(url.path), fm.fileExists(atPath: url.path) else { continue }
                // An existing symlink means this item was already relocated.
                if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                   values.isSymbolicLink == true { continue }
                seen.insert(url.path)
                found.append(SupportItem(kind: kind, url: url, size: FileSize.onDisk(of: url)))
            }
        }

        return found.sorted { $0.size > $1.size }
    }

    /// Finds ~/Library items for `app` that are already symlinks elsewhere —
    /// candidates to fold into the ledger via "Considérer comme déplacée"
    /// rather than to move. A dangling symlink (target no longer exists) is
    /// skipped: there is nothing left to track.
    static func locateAdoptable(app: InstalledApp) -> [AdoptableItem] {
        let fm = FileManager.default
        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        var found: [AdoptableItem] = []
        var seen = Set<String>()

        for kind in SupportItem.Kind.allCases {
            let base = library.appendingPathComponent(kind.librarySubpath)
            for name in candidateNames(for: kind, app: app) {
                let url = base.appendingPathComponent(name)
                guard !seen.contains(url.path) else { continue }
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values?.isSymbolicLink == true else { continue }
                let resolved = url.resolvingSymlinksInPath()
                guard fm.fileExists(atPath: resolved.path) else { continue }
                seen.insert(url.path)
                found.append(AdoptableItem(kind: kind, originalURL: url, resolvedURL: resolved,
                                           size: FileSize.onDisk(of: resolved)))
            }
        }

        return found.sorted { $0.size > $1.size }
    }
}
