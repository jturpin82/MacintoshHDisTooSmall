import SwiftUI

@main
struct MacintoshHDisTooSmallApp: App {
    var body: some Scene {
        WindowGroup("MacintoshHDisTooSmall") {
            ContentView()
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
