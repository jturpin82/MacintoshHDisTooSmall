import Foundation

enum SupportFileLocator {
    /// Bundle identifier components too generic to name anything on disk.
    /// Probing `~/.app` or `~/.com` would only produce noise.
    private static let genericStems: Set<String> = [
        "com", "org", "net", "io", "ai", "co", "uk", "dev", "app", "apps",
        "desktop", "client", "mac", "macos", "osx", "gui", "electron",
        "inc", "ltd", "labs", "software", "the"
    ]

    /// Home entries shared by the whole system or holding credentials: never
    /// proposed, whatever an app happens to be called — "Local.app" must not
    /// offer to move `~/.local`, which belongs to everything else too.
    /// Lowercased — the startup volume is case-insensitive, so `~/.SSH` and
    /// `~/.ssh` are the same folder and both must be refused.
    private static let protectedHomeNames: Set<String> = [
        ".trash", ".ssh", ".gnupg", ".aws", ".config", ".cache", ".local"
    ]

    /// Name fragments worth probing outside ~/Library: the app's own name and
    /// every component of its bundle identifier. Apps that keep their data in
    /// the home folder rarely name it after the bundle in full — LM Studio
    /// ships as `Bionic.app` but stores its models in `~/.lmstudio`, which
    /// only the middle component of its identifier gives away.
    ///
    /// Existence is then tested exactly, so a fragment that matches nothing
    /// costs one `stat` and disappears.
    private static func homeStems(name: String, bundleID: String?) -> [String] {
        var raw = [name, name.replacingOccurrences(of: " ", with: "")]
        raw += bundleID?.split(separator: ".").map(String.init) ?? []

        var seen = Set<String>()
        var stems: [String] = []
        for stem in raw {
            let lowered = stem.lowercased()
            guard lowered.count >= 3, !genericStems.contains(lowered) else { continue }
            for variant in [stem, lowered] where !seen.contains(variant) {
                seen.insert(variant)
                stems.append(variant)
            }
        }
        return stems
    }

    /// Candidate directory names for a given kind, most specific first.
    private static func candidateNames(for kind: SupportItem.Kind,
                                       name: String,
                                       bundleID: String?) -> [String] {
        if kind.isOutsideLibrary {
            let stems = homeStems(name: name, bundleID: bundleID)
            guard kind == .homeHidden else { return stems }
            return stems.map { "." + $0 }.filter { !protectedHomeNames.contains($0.lowercased()) }
        }

        var stems: [String] = []
        if let bundleID, !bundleID.isEmpty { stems.append(bundleID) }
        stems.append(name)

        switch kind {
        case .savedState:
            return stems.map { "\($0).savedState" }
        case .httpStorages:
            return stems + stems.map { "\($0).binarycookies" }
        case .containers:
            // Sandbox containers are always keyed by bundle identifier.
            return bundleID.map { [$0] } ?? []
        default:
            return stems
        }
    }

    /// Finds cache / configuration items belonging to `app` under ~/Library
    /// and in the home folder itself.
    /// Matching is on exact directory names only — never fuzzy — and the user
    /// confirms the list before anything is moved.
    static func locate(app: InstalledApp) -> [SupportItem] {
        locate(name: app.name, bundleID: app.bundleID)
    }

    /// Same, for an app known only through its ledger entry — its bundle may
    /// have left /Applications without leaving a symlink behind.
    static func locate(name: String, bundleID: String?) -> [SupportItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var found: [SupportItem] = []
        var seen = Set<String>()

        for kind in SupportItem.Kind.allCases {
            let base = kind.baseURL(inHome: home)
            for candidate in candidateNames(for: kind, name: name, bundleID: bundleID)
                where !candidate.isEmpty && candidate != "." {
                let url = base.appendingPathComponent(candidate)
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

    /// Finds items for `app` that are already symlinks elsewhere — candidates
    /// to fold into the ledger via "Considérer comme déplacée" rather than to
    /// move. A dangling symlink (target no longer exists) is skipped: there is
    /// nothing left to track.
    static func locateAdoptable(app: InstalledApp) -> [AdoptableItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var found: [AdoptableItem] = []
        var seen = Set<String>()

        for kind in SupportItem.Kind.allCases {
            let base = kind.baseURL(inHome: home)
            for candidate in candidateNames(for: kind, name: app.name, bundleID: app.bundleID)
                where !candidate.isEmpty && candidate != "." {
                let url = base.appendingPathComponent(candidate)
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
