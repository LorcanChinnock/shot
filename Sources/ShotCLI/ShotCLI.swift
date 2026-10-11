import Foundation
import ShotCore

/// The `shot` command line: `shot mcp`, the MCP server AI agents talk to, the headless media commands, and `--version`.
/// It ships inside the app as `Contents/MacOS/shot-cli`, so it reads the app's settings to find the captures.
@main
enum ShotCLI {
    static func main() async {
        let program = URL(fileURLWithPath: CommandLine.arguments.first ?? "shot").lastPathComponent
        let command: ShotCommand
        do {
            command = try ShotCommand.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            let prefix = if case let .usage(name?, _) = error { "\(program) \(name)" } else { program }
            printError("\(prefix): \(error.message)")
            if case let .usage(name, _) = error {
                printError(ShotCommand.usage(name, program: program))
            }
            exit(error.exitCode)
        }
        switch command {
        case .mcp:
            let app = appBundle()
            await serve(folder: captureFolder(app: app), version: version(of: app))
        case .version:
            let app = appBundle()
            print("Shot \(version(of: app))")
            print("Bundle: \(app?.bundleIdentifier ?? "none, reading the \(fallbackSuite) settings")")
            print("Captures: \(captureFolder(app: app).path)")
        case let .help(name):
            print(ShotCommand.usage(name, program: program))
        default:
            do {
                let result = try await ShotCommands.run(command)
                if result["truncated"] == .bool(true) {
                    printError("\(program) \(command.name): GIFs stop at \(Int(GIFExporter.maxDuration)) seconds, so this one ends early")
                }
                print(ShotCommand.json(result))
            } catch {
                printError("\(program) \(command.name): \(error.message)")
                exit(error.exitCode)
            }
        }
    }

    /// The folder the app saves captures to, from its settings.
    static func captureFolder(app: Bundle?) -> URL {
        let store = defaultsStore(app: app)
        // Without the defaults, saveAfterCapture reads false and the capture folder silently becomes the temporary one.
        Preferences.registerDefaults(in: store)
        return Preferences(store: store).captureFolder
    }

    /// Reads one JSON-RPC message per line until the client closes stdin. Only replies go to stdout, since any other
    /// line there breaks the protocol; `FileHandle` writes straight through, so each reply is flushed as it's written.
    static func serve(folder: URL, version: String) async {
        let server = AgentTools.live(folder: folder).server(version: version)
        printError("Shot MCP server \(version), reading \(folder.path)")
        while let line = readLine(strippingNewline: true) {
            if let reply = await server.respond(to: line) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
    }

    /// The app this executable is inside. `Bundle.main` finds it when run by its real path, but not through a symlink
    /// such as Homebrew's `shot`, so that path is resolved first.
    static func appBundle() -> Bundle? {
        if Bundle.main.bundleIdentifier != nil {
            return Bundle.main
        }
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return nil
        }
        // Shot.app/Contents/MacOS/shot-cli
        let bundle = Bundle(url: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        return bundle?.bundleIdentifier != nil ? bundle : nil
    }

    static func version(of app: Bundle?) -> String {
        app?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// The settings of a dev build, for a bare `.build/debug/ShotCLI` with no bundle around it.
    static var fallbackSuite: String {
        ProcessInfo.processInfo.environment["SHOT_DEFAULTS"] ?? "dev.lorcan.Shot.dev"
    }

    /// The app's own settings. Those are `.standard` when `Bundle.main` is the app, where `UserDefaults(suiteName:)`
    /// would return nil for its ID.
    static func defaultsStore(app: Bundle?) -> UserDefaults {
        if let app, app == Bundle.main {
            return .standard
        }
        return UserDefaults(suiteName: app?.bundleIdentifier ?? fallbackSuite) ?? .standard
    }

    static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
