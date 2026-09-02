import Foundation

/// One filesystem entry that was moved out of its original location.
struct MovedItem: Codable, Hashable, Identifiable {
    /// "bundle" for the .app itself, otherwise a `SupportItem.Kind` raw value.
    let kind: String
    let originalPath: String
    let relocatedPath: String
    /// Whether a symlink was left behind at `originalPath`.
    let symlinkCreated: Bool
    let bytes: Int64

    var id: String { originalPath }
    var isBundle: Bool { kind == "bundle" }
    var supportKind: SupportItem.Kind? { SupportItem.Kind(rawValue: kind) }

    var originalURL: URL { URL(fileURLWithPath: originalPath) }
    var relocatedURL: URL { URL(fileURLWithPath: relocatedPath) }

    static let bundleKind = "bundle"
}

/// Everything that was moved for a single application, and how to put it back.
struct MoveRecord: Codable, Hashable, Identifiable {
    let appName: String
    let bundleID: String?
    /// Destination folder the user chose for this move. Several apps can share
    /// the same value: each item's own `relocatedPath` is what actually
    /// changes between them.
    let destinationRoot: String
    let movedAt: Date
    var items: [MovedItem]

    var id: String { appName }
    var destinationRootURL: URL { URL(fileURLWithPath: destinationRoot) }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    var bundleItem: MovedItem? { items.first(where: \.isBundle) }
}
