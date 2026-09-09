// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Toothpaste",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Toothpaste",
            path: "Sources/Toothpaste",
            // Swift 5 mode: strict concurrency fights AppKit callbacks harder than
            // it helps at this size. Revisit once the app has settled.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Diagnostic tool, not part of the app. `typespike --dump-map --layout <id>`
        // shows which characters a keyboard layout can produce; nothing in the UI
        // exposes that yet.
        .executableTarget(
            name: "typespike",
            path: "Sources/TypeSpike",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
