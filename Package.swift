// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeskBreak",
    platforms: [
        // MenuBarExtra, SMAppService and SuspendingClock all require macOS 13.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DeskBreak", targets: ["DeskBreak"])
    ],
    targets: [
        // Pure scheduling, logging and persistence logic. Foundation only, so it can be unit tested.
        .target(
            name: "DeskBreakCore"
        ),
        // The menu bar app: SwiftUI, AppKit, UserNotifications, ServiceManagement.
        .executableTarget(
            name: "DeskBreak",
            dependencies: ["DeskBreakCore"]
        ),
        .testTarget(
            name: "DeskBreakCoreTests",
            dependencies: ["DeskBreakCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
