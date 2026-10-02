// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shot",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ShotCore"),
        .executableTarget(name: "Shot", dependencies: ["ShotCore"]),
        .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"]),
    ]
)
