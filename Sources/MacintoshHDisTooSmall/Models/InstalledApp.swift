import Foundation

/// An application bundle found in one of the scanned Applications folders.
struct InstalledApp: Identifiable, Hashable {
    /// Path of the bundle as it appears in /Applications (may itself be a symlink).
    let installedURL: URL
    let name: String
    let bundleID: String?
    let version: String?
    /// Names the bundle calls itself from the inside — CFBundleName,
    /// CFBundleDisplayName, CFBundleExecutable — when they differ from the
    /// file name. An app is not always shipped under the name it is sold
    /// under: LM Studio installs as `Bionic.app`, and only these fields carry
    /// the name its data folder is likely to be built from.
    let alternateNames: [String]
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

        let fileName = self.name
        var alternates: [String] = []
        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            guard let value = info?[key] as? String,
                  !value.isEmpty, value != fileName, !alternates.contains(value) else { continue }
            alternates.append(value)
        }
        self.alternateNames = alternates
    }
}
