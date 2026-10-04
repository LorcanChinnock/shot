// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shot",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "ShotCore"),
        .executableTarget(
            name: "Shot",
            dependencies: ["ShotCore", .product(name: "Sparkle", package: "Sparkle")],
            // bundle.sh copies Sparkle.framework into Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"]),
    ]
)
