// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacintoshHDisTooSmall",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacintoshHDisTooSmall",
            path: "Sources/MacintoshHDisTooSmall"
        )
    ]
)
