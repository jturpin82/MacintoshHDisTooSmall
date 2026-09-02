import Foundation

/// One line in the sidebar. Either an app currently present in /Applications,
/// or an app only known through the ledger (moved out without leaving a symlink).
struct AppRow: Identifiable, Hashable {
    let id: String
    let name: String
    let app: InstalledApp?
    let record: MoveRecord?
    let size: Int64?

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
