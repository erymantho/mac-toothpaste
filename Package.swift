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
        // Diagnostic tool, not part of the app. `typespike --dump-map --layout <id> [text]`
        // prints the keys that would type each character of a sample: keycode, modifiers,
        // or the dead-key pair that composes it. Settings → Layout check only says which
        // characters cannot be typed.
        .executableTarget(
            name: "typespike",
            path: "Sources/TypeSpike",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
