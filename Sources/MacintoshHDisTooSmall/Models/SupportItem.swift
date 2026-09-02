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

        /// Path of the containing directory, relative to ~/Library.
        var librarySubpath: String {
            switch self {
            case .applicationSupport: return "Application Support"
            case .caches: return "Caches"
            case .containers: return "Containers"
            case .logs: return "Logs"
            case .savedState: return "Saved Application State"
            case .httpStorages: return "HTTPStorages"
            case .webKit: return "WebKit"
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
            }
        }
    }

    let kind: Kind
    let url: URL
    var size: Int64

    var id: String { url.path }
}
