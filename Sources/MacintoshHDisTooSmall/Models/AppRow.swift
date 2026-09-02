import Foundation

/// One line in the sidebar. Either an app currently present in /Applications,
/// or an app only known through the ledger (moved out without leaving a symlink).
struct AppRow: Identifiable, Hashable {
    let id: String
    let name: String
    let app: InstalledApp?
    let record: MoveRecord?
    /// Size of the .app bundle alone.
    let bundleSize: Int64?
    /// Combined size of the caches and configuration files that belong to it.
    let supportSize: Int64?

    /// What the app really costs: bundle plus everything that comes with it.
    var size: Int64? {
        guard bundleSize != nil || supportSize != nil else { return nil }
        return (bundleSize ?? 0) + (supportSize ?? 0)
    }

    var isRelocated: Bool { record != nil }
    var bundleID: String? { app?.bundleID ?? record?.bundleID }

    /// Path used to fetch the Finder icon, if the bundle can still be reached.
    var iconPath: String? {
        if let app, FileManager.default.fileExists(atPath: app.installedURL.path) {
            return app.installedURL.path
        }
        if let path = record?.bundleItem?.relocatedPath,
           FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }
}
