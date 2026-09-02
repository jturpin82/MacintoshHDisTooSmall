import Foundation

/// An application bundle found in one of the scanned Applications folders.
struct InstalledApp: Identifiable, Hashable {
    /// Path of the bundle as it appears in /Applications (may itself be a symlink).
    let installedURL: URL
    let name: String
    let bundleID: String?
    let version: String?
    /// True when /Applications/<name>.app is a symlink, i.e. the bundle already lives elsewhere.
    let isRelocated: Bool

    var id: String { installedURL.path }

    init(installedURL: URL) {
        self.installedURL = installedURL
        self.name = installedURL.deletingPathExtension().lastPathComponent

        let values = try? installedURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        self.isRelocated = values?.isSymbolicLink ?? false

        // Follow the symlink when reading Info.plist so relocated apps still report metadata.
        let plistURL = installedURL
            .resolvingSymlinksInPath()
            .appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: plistURL)
        self.bundleID = info?["CFBundleIdentifier"] as? String
        self.version = (info?["CFBundleShortVersionString"] as? String)
            ?? (info?["CFBundleVersion"] as? String)
    }
}
