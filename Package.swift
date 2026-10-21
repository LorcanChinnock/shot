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
        // Everything with no window: the model, rendering, video, GIF, agents and MCP, preferences and the gallery.
        .target(name: "ShotCore", swiftSettings: extractingStrings("ShotCore")),
        .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"]),
        .executableTarget(
            name: "Shot",
            dependencies: ["ShotCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: extractingStrings("Shot"),
            // bundle.sh copies Sparkle.framework into Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // The MCP server and command line. bundle.sh copies it into the app as shot-cli: a "shot" there would be the
        // app's own Shot executable on a case-insensitive volume.
        .executableTarget(name: "ShotCLI", dependencies: ["ShotCore"]),
    ]
)
