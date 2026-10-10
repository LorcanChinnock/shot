// swift-tools-version: 6.0
// A stand-in app to screenshot and record for Shot's docs. Not part of Shot's build; see README.md.
import PackageDescription

let package = Package(
    name: "ShotDemo",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "ShotDemo")]
)
