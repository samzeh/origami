// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "origami",
    platforms: [
        // SCScreenshotManager (one-shot window capture) is macOS 14+;
        // SCStreamConfiguration.includeChildWindows is 14.2+. macOS 15 is a safe
        // floor for a directly-distributed app in 2026.
        .macOS(.v15)
    ],
    targets: [
        // The reusable guts. The menu bar app and the CLI harness both link this.
        .target(name: "OrigamiKit"),

        // The menu bar app: intercepts Cmd+Q and runs the swap.
        .executableTarget(name: "OrigamiClose", dependencies: ["OrigamiKit"]),

        // A terminal harness: find the frontmost window, capture it, report timings.
        .executableTarget(name: "origami-capture", dependencies: ["OrigamiKit"]),

        .testTarget(name: "OrigamiKitTests", dependencies: ["OrigamiKit"]),
    ]
)
