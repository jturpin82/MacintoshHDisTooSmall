import SwiftUI
import AppKit

/// A window miniaturized into the Dock is not always brought back by clicking
/// the app's icon: with a plain SwiftUI `WindowGroup`, AppKit finds no visible
/// window to order front, activates the app, and leaves the window stuck in the
/// Dock — the app looks frozen. Deminiaturizing by hand is the fix.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        for window in sender.windows where window.isMiniaturized {
            window.deminiaturize(nil)
        }
        return true
    }
}

@main
struct MacintoshHDisTooSmallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MacintoshHDisTooSmall") {
            ContentView()
        }
        .defaultSize(width: 1000, height: 640)
        // Without this the window's minimum comes from the content laying
        // itself out, which a restore from the Dock can catch mid-flight.
        .windowResizability(.contentMinSize)
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
