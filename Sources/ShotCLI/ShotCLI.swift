import Foundation
import ShotCore

/// The `shot` command line: `shot mcp`, the MCP server AI agents talk to, the headless media commands, `shot capture`
/// and `shot record`, which ask the running app, `shot watch`, and `--version`. It ships inside the app as `Contents/MacOS/shot-cli`, so it reads the
/// app's settings to find the captures.
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
            await serve(folder: captureFolder(app: app), version: version(of: app), app: app)
        case .version:
            let app = appBundle()
            print("Shot \(version(of: app))")
            print("Bundle: \(app?.bundleIdentifier ?? "none, reading the \(fallbackSuite) settings")")
            print("Captures: \(captureFolder(app: app).path)")
        case let .help(name):
            print(ShotCommand.usage(name, program: program))
        case .capture, .windows:
            let request = if case let .capture(target) = command { AgentRequest(.capture, target: target) } else { AgentRequest(.windows) }
            do {
                print(ShotCommand.json(.object(try await ask(request, app: appBundle()))))
            } catch {
                printError("\(program) \(command.name): \(error.message)")
                exit(error.exitCode)
            }
        case let .record(action):
            let request = switch action {
            case let .start(target, duration): AgentRequest(.record, target: target, duration: duration)
            case let .stop(id): AgentRequest(.stop, id: id)
            case .status: AgentRequest(.status)
            }
            do {
                let result = try await ask(request, app: appBundle())
                print(ShotCommand.json(.object(result)))
                if let path = result["path"]?.string {
                    printError("\(program) frames \"\(path)\" shows what happened in it.")
                } else if let id = result["id"]?.string {
                    printError("Recording. \(program) record --stop \(id) ends it; it stops itself after \(Int(AgentRequest.maximumDuration / 60)) minutes.")
                }
            } catch {
                printError("\(program) \(command.name): \(error.message)")
                exit(error.exitCode)
            }
        case let .watch(options):
            await watch(options, folder: captureFolder(app: appBundle()), program: program)
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
    static func serve(folder: URL, version: String, app: Bundle?) async {
        let server = AgentTools.live(folder: folder) { request throws(ShotCommandError) in
            try await ask(request, app: app)
        }.server(version: version)
        printError("Shot MCP server \(version), reading \(folder.path)")
        while let line = readLine(strippingNewline: true) {
            if let reply = await server.respond(to: line) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
    }

    /// Prints the next capture to arrive in `folder`, or with `follow`, one line for each until the timeout or ^C. Each
    /// line is written straight through, so a reader sees it at once.
    static func watch(_ options: ShotCommand.WatchOptions, folder: URL, program: String) async {
        let tools = AgentTools.live(folder: folder)
        let span = options.timeout.map { "\(String(format: "%g", $0)) second\($0 == 1 ? "" : "s")" } ?? ""
        printError("Watching \(folder.path) for \(options.follow ? "new captures" : "the next capture")\(span.isEmpty ? "" : ", for up to \(span)")")
        var found = false
        await CaptureWatch.watch(kind: options.kind, timeout: options.timeout, entries: tools.entries) { entry in
            found = true
            let line = options.follow ? ShotCommand.jsonLine(tools.metadata(entry)) : ShotCommand.json(tools.metadata(entry))
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
            return options.follow
        }
        if !found, !options.follow {
            let error = ShotCommandError.noInput("no new capture in \(folder.path) within \(span)")
            printError("\(program) watch: \(error.message)")
            exit(error.exitCode)
        }
    }

    /// Sends `request` to the running app, opening it in the background first if it isn't running.
    static func ask(_ request: AgentRequest, app: Bundle?) async throws(ShotCommandError) -> [String: JSONValue] {
        // Read on each request, so the MCP server, which runs for a whole session, sees the setting change.
        let enabled = Preferences(store: defaultsStore(app: app)).agentCapture
        return try await AgentSocket.ask(request, bundleID: app?.bundleIdentifier ?? fallbackSuite, enabled: enabled, timeout: timeout(for: request))
    }

    /// How long to wait for the app's answer: a stop or a timed recording waits for the video to be written too.
    static func timeout(for request: AgentRequest) -> Duration {
        switch request.op {
        case .capture: .seconds(30 + (request.waitStable ?? 0))
        case .status, .windows: .seconds(30)
        case .record: .seconds((request.duration ?? 0) + 120)
        case .stop: .seconds(120)
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
