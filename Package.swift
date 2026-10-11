// swift-tools-version: 6.0
import PackageDescription

// ShotModel needs only Foundation, so CI builds and tests it on Linux. Everything else needs Apple frameworks.
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "ShotModel"),
    .testTarget(name: "ShotModelTests", dependencies: ["ShotModel"]),
]

#if os(macOS)
dependencies += [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
]
targets += [
    .target(name: "ShotCore", dependencies: ["ShotModel"]),
    .executableTarget(
        name: "Shot",
        dependencies: ["ShotCore", .product(name: "Sparkle", package: "Sparkle")],
        // bundle.sh copies Sparkle.framework into Contents/Frameworks.
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"]),
]
#endif

let package = Package(
    name: "Shot",
    platforms: [.macOS(.v15)],
    dependencies: dependencies,
    targets: targets
)
