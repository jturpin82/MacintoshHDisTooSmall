import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppIconView: View {
    let path: String?
    var side: CGFloat = 28

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
    }

    private var icon: NSImage {
        if let path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
