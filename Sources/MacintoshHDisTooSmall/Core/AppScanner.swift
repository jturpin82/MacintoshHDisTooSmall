import Foundation

enum AppScanner {
    static let searchPaths = ["/Applications", "/Applications/Utilities"]

    /// Lists every .app bundle directly inside the scanned folders, excluding ourselves.
    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let ownBundleID = Bundle.main.bundleIdentifier
        var apps: [InstalledApp] = []

        for path in searchPaths {
            let directory = URL(fileURLWithPath: path)
            let contents = (try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                        options: [.skipsHiddenFiles])) ?? []
            for url in contents where url.pathExtension == "app" {
                let app = InstalledApp(installedURL: url)
                if let ownBundleID, app.bundleID == ownBundleID { continue }
                apps.append(app)
            }
        }

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
