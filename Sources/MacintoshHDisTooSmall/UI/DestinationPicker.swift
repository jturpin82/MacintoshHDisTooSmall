import AppKit

@MainActor
enum DestinationPicker {
    /// Asks for a folder to move applications into.
    static func choose(startingAt path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Dossier qui accueillera les applications déplacées"
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks for one extra item to move along with an app. Hidden entries are
    /// shown: the folders worth adding by hand are mostly dotted ones the
    /// automatic search could not name (`~/.lmstudio` and the like).
    static func chooseSupportItem() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.prompt = "Ajouter"
        panel.message = "Dossier ou fichier à déplacer avec l'application"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        return panel.runModal() == .OK ? panel.url : nil
    }
}
