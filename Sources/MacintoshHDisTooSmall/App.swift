import SwiftUI
import AppKit

@main
struct MacintoshHDisTooSmallApp: App {
    var body: some Scene {
        WindowGroup("MacintoshHDisTooSmall") {
            ContentView()
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de MacintoshHDisTooSmall") { showAboutPanel() }
            }
            CommandGroup(replacing: .newItem) {}
        }
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: """
            Par Jonathan Turpin

            Déplace des applications hors de /Applications vers un autre volume, \
            avec leurs caches et fichiers de configuration, et sait tout remettre en place.
            """,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "MacintoshHDisTooSmall",
            .credits: credits
        ])
    }
}
