// swift-tools-version: 6.0
import PackageDescription

// A stand-in app to capture in QA runs, guide screenshots. Its own package, so the main build
// and CI never compile it. Build and open it with `make demo`.
let package = Package(
    name: "MugCo",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "MugCo")]
)
