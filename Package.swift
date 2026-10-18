// swift-tools-version: 6.0
import PackageDescription

// On a Mac, every build extracts the strings the app shows into .build/stringsdata, one folder per target since two
// targets can have files of the same name. scripts/strings.sh syncs them into Resources/Localizable.xcstrings.
func extractingStrings(_ target: String) -> [SwiftSetting] {
    #if os(macOS)
    let path = "\(Context.packageDirectory)/.build/stringsdata/\(target)"
    return [.unsafeFlags(["-emit-localized-strings", "-emit-localized-strings-path", path])]
    #else
    return []
    #endif
}

// ShotModel needs only Foundation, and ShotCore keeps its Apple framework calls under #if canImport until they move to
// ShotCoreApple, so CI builds and tests both on Linux. Everything else needs Apple frameworks.
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "ShotModel"),
    .testTarget(name: "ShotModelTests", dependencies: ["ShotModel"]),
    .target(name: "ShotCore", dependencies: ["ShotModel"], swiftSettings: extractingStrings("ShotCore")),
    .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"]),
]

#if os(macOS)
dependencies += [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
]
targets += [
    // The Apple implementations of ShotCore's protocols. It re-exports ShotCore, so the app and ShotCLI import only this.
    .target(name: "ShotCoreApple", dependencies: ["ShotCore"], swiftSettings: extractingStrings("ShotCoreApple")),
    .executableTarget(
        name: "Shot",
        dependencies: ["ShotCoreApple", .product(name: "Sparkle", package: "Sparkle")],
        swiftSettings: extractingStrings("Shot"),
        // bundle.sh copies Sparkle.framework into Contents/Frameworks.
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    // The MCP server and future command line. bundle.sh copies it into the app as shot-cli: a "shot" there would be
    // the app's own Shot executable on a case-insensitive volume.
    .executableTarget(name: "ShotCLI", dependencies: ["ShotCoreApple"]),
    .testTarget(name: "ShotCoreAppleTests", dependencies: ["ShotCoreApple"]),
]
#endif

let package = Package(
    name: "Shot",
    platforms: [.macOS(.v15)],
    dependencies: dependencies,
    targets: targets
)
