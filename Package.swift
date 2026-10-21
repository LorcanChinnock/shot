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
// ShotCoreApple, so CI builds and tests both on Linux, with the command line on ShotCoreLinux. The app needs Apple
// frameworks.
var dependencies: [Package.Dependency] = []
var products: [Product] = []
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
#elseif os(Linux)
targets += [
    // The Linux implementations of ShotCore's protocols, as they come (#656). It re-exports ShotCore, so ShotCLI
    // imports only this.
    .target(name: "ShotCoreLinux", dependencies: ["ShotCore", "CPNG", "CTurboJPEG", "CCairo", "CPango", "CXCB", "CDBus"]),
    // The C libraries it codes images with, through their APIs that report errors rather than jumping out of them.
    .systemLibrary(name: "CPNG", pkgConfig: "libpng", providers: [.apt(["libpng-dev"])]),
    .systemLibrary(name: "CTurboJPEG", pkgConfig: "libturbojpeg", providers: [.apt(["libturbojpeg0-dev"])]),
    // The library it draws with.
    .systemLibrary(name: "CCairo", pkgConfig: "cairo", providers: [.apt(["libcairo2-dev"])]),
    // The library it shapes text with, and fontconfig, which finds its fonts.
    .systemLibrary(name: "CPango", pkgConfig: "pangocairo", providers: [.apt(["libpango1.0-dev"])]),
    // The X server's client library, and its Composite and RandR extensions, which it captures an X11 session with.
    .systemLibrary(name: "CXCB", pkgConfig: "xcb-composite", providers: [.apt(["libxcb1-dev", "libxcb-composite0-dev", "libxcb-randr0-dev"])]),
    // The session bus's client library, which it asks the desktop portal for screenshots through on Wayland.
    .systemLibrary(name: "CDBus", pkgConfig: "dbus-1", providers: [.apt(["libdbus-1-dev"])]),
    .executableTarget(name: "ShotCLI", dependencies: ["ShotCoreLinux"]),
    // CXCB, so the X11 tests can put windows on the X server they start, and CDBus, so the portal's tests can stand in
    // for it on the bus they start.
    .testTarget(name: "ShotCoreLinuxTests", dependencies: ["ShotCoreLinux", "CXCB", "CDBus"]),
]
// Linux has no app to put it in, so it's built as `shot`.
products += [.executable(name: "shot", targets: ["ShotCLI"])]
#endif

let package = Package(
    name: "Shot",
    platforms: [.macOS(.v15)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
