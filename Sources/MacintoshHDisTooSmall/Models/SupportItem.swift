import Foundation

/// A cache / configuration directory belonging to an application, living outside its bundle.
struct SupportItem: Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case applicationSupport
        case caches
        case containers
        case logs
        case savedState
        case httpStorages
        case webKit
        case homeHidden
        case xdgConfig
        case xdgCache
        case xdgData
        case custom

        /// Path of the containing directory, relative to the home folder.
        /// Empty for `homeHidden`, whose items sit at the root of ~ itself.
        var homeSubpath: String {
            switch self {
            case .applicationSupport: return "Library/Application Support"
            case .caches: return "Library/Caches"
            case .containers: return "Library/Containers"
            case .logs: return "Library/Logs"
            case .savedState: return "Library/Saved Application State"
            case .httpStorages: return "Library/HTTPStorages"
            case .webKit: return "Library/WebKit"
            case .homeHidden: return ""
            case .xdgConfig: return ".config"
            case .xdgCache: return ".cache"
            case .xdgData: return ".local/share"
            // Never probed for — a manually added item carries its own full path.
            case .custom: return ""
            }
        }

        func baseURL(inHome home: URL) -> URL {
            homeSubpath.isEmpty ? home : home.appendingPathComponent(homeSubpath)
        }

        /// True for the kinds living outside ~/Library, where an app's data
        /// folder is named after the app rather than placed by macOS.
        var isOutsideLibrary: Bool {
            switch self {
            case .homeHidden, .xdgConfig, .xdgCache, .xdgData, .custom: return true
            default: return false
            }
        }

        var displayName: String {
            switch self {
            case .applicationSupport: return "Application Support"
            case .caches: return "Cache"
            case .containers: return "Conteneur (sandbox)"
            case .logs: return "Journaux"
            case .savedState: return "État de fenêtres"
            case .httpStorages: return "Stockage HTTP"
            case .webKit: return "WebKit"
            case .homeHidden: return "Dossier utilisateur"
            case .xdgConfig: return "Configuration (.config)"
            case .xdgCache: return "Cache (.cache)"
            case .xdgData: return "Données (.local/share)"
            case .custom: return "Dossier ajouté"
            }
        }

        /// Top-level folder name under a destination root, mirroring ~/Library
        /// one level down instead of nesting per app — every app moved to the
        /// same destination shares these folders.
        var destinationFolderName: String {
            switch self {
            case .applicationSupport: return "ApplicationSupport"
            case .caches: return "Caches"
            case .containers: return "Containers"
            case .logs: return "Logs"
            case .savedState: return "SavedApplicationState"
            case .httpStorages: return "HTTPStorages"
            case .webKit: return "WebKit"
            case .homeHidden: return "Home"
            case .xdgConfig: return "Config"
            case .xdgCache: return "CacheXDG"
            case .xdgData: return "LocalShare"
            case .custom: return "Autres"
            }
        }

        var symbolName: String {
            switch self {
            case .applicationSupport: return "folder"
            case .caches: return "clock.arrow.circlepath"
            case .containers: return "shippingbox"
            case .logs: return "doc.text"
            case .savedState: return "macwindow"
            case .httpStorages: return "network"
            case .webKit: return "globe"
            case .homeHidden: return "house"
            case .xdgConfig: return "slider.horizontal.3"
            case .xdgCache: return "clock.arrow.circlepath"
            case .xdgData: return "archivebox"
            case .custom: return "folder.badge.plus"
            }
        }
    }

    let kind: Kind
    let url: URL
    var size: Int64

    var id: String { url.path }
}

extension SupportItem {
    /// Builds an item for a folder the user picked by hand, filing it under
    /// the kind whose base directory contains it so it lands in the same
    /// destination folder as anything found automatically there.
    init(manuallyAdded url: URL) {
        let standardized = url.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser
        let parent = standardized.deletingLastPathComponent().standardizedFileURL
        let matched = Kind.allCases.first {
            $0 != .custom && $0.baseURL(inHome: home).standardizedFileURL == parent
        }
        self.init(kind: matched ?? .custom, url: standardized, size: FileSize.onDisk(of: standardized))
    }
}

/// A ~/Library item that turned out to already be a symlink elsewhere —
/// evidence the app was relocated by some other means, found while looking
/// for something to fold into the ledger rather than something to move.
struct AdoptableItem: Identifiable, Hashable {
    let kind: SupportItem.Kind
    let originalURL: URL
    let resolvedURL: URL
    let size: Int64

    var id: String { originalURL.path }
}
