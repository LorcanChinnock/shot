// swift-tools-version: 6.0
import PackageDescription

// Every build extracts the strings the app shows into .build/stringsdata, one folder per target since two targets can
// have files of the same name. scripts/strings.sh syncs them into Resources/Localizable.xcstrings.
func extractingStrings(_ target: String) -> [SwiftSetting] {
    let path = "\(Context.packageDirectory)/.build/stringsdata/\(target)"
    return [.unsafeFlags(["-emit-localized-strings", "-emit-localized-strings-path", path])]
}

let package = Package(
    name: "Shot",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // Everything with no window: the model, rendering, video, GIF, preferences and the gallery.
        // ShotCore is optimised even in debug builds: the scrolling composer's per-pixel loops make the tests take
        // minutes longer unoptimised. -enable-testing stays on, so @testable imports still work.
        .target(name: "ShotCore", swiftSettings: extractingStrings("ShotCore") + [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"]),
        // Replays recorded scroll scenarios through ScrollStitcher and scores the result: scripts/scroll-lab.
        .executableTarget(name: "ScrollLab", dependencies: ["ShotCore"]),
        .executableTarget(
            name: "Shot",
            dependencies: ["ShotCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: extractingStrings("Shot"),
            // bundle.sh copies Sparkle.framework into Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
