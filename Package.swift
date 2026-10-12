// swift-tools-version: 6.0
import PackageDescription

// ShotModel needs only Foundation, so CI builds and tests it on Linux. Everything else needs Apple frameworks.
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "ShotModel"),
    .testTarget(name: "ShotModelTests", dependencies: ["ShotModel"]),
]

#if os(macOS)
// Every build extracts the strings the app shows into .build/stringsdata, one folder per target since two targets can
// have files of the same name. scripts/strings.sh syncs them into Resources/Localizable.xcstrings.
func extractingStrings(_ target: String) -> [SwiftSetting] {
    let path = "\(Context.packageDirectory)/.build/stringsdata/\(target)"
    return [.unsafeFlags(["-emit-localized-strings", "-emit-localized-strings-path", path])]
}

dependencies += [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
]
targets += [
    .target(name: "ShotCore", dependencies: ["ShotModel"], swiftSettings: extractingStrings("ShotCore")),
    .executableTarget(
        name: "Shot",
        dependencies: ["ShotCore", .product(name: "Sparkle", package: "Sparkle")],
        swiftSettings: extractingStrings("Shot"),
        // bundle.sh copies Sparkle.framework into Contents/Frameworks.
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    // The MCP server and future command line. bundle.sh copies it into the app as shot-cli: a "shot" there would be
    // the app's own Shot executable on a case-insensitive volume.
    .executableTarget(name: "ShotCLI", dependencies: ["ShotCore"]),
    .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"]),
]
#endif

let package = Package(
    name: "Shot",
    platforms: [.macOS(.v15)],
    dependencies: dependencies,
    targets: targets
)
