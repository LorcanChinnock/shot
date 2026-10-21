import Foundation
#if os(macOS)
import ShotCoreApple
#else
import ShotCoreLinux
#endif

/// The `shot` command line: `shot mcp`, the MCP server AI agents talk to, the headless media commands, `shot capture`
/// and `shot record`, which ask the running app, `shot latest`, `list` and `get`, which read captures as the MCP tools
/// do, `shot watch`, `shot doctor`, and `--version`. It ships inside the app as `Contents/MacOS/shot-cli`, so it reads the
/// app's settings to find the captures. On Linux, where it's `shot`, only `Doctor.linuxCommands` run so far: the image
/// commands, those that read captures, and `shot capture` and `shot windows`, which ask `shot serve` rather than an app.
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
        case .doctor:
            #if os(macOS)
            let checks = Doctor.checks(await doctorFacts(app: appBundle()))
            #else
            let checks = Doctor.checks(await linuxDoctorFacts())
            #endif
            print(ShotCommand.json(Doctor.json(checks)))
            if checks.contains(where: { $0.outcome == .fail }) {
                exit(1)
            }
        case .latest, .list, .get:
            do {
                let app = appBundle()
                print(ShotCommand.json(try readCaptures(command, tools: captureTools(folder: captureFolder(app: app), app: app))))
            } catch {
                printError("\(program) \(command.name): \(error.message)")
                exit(error.exitCode)
            }
        case let .watch(options):
            await watch(options, folder: captureFolder(app: appBundle()), program: program)
        case .capture, .windows:
            var request = AgentRequest(.windows)
            if case let .capture(target) = command {
                request = AgentRequest(.capture, target: target)
                request.origin = ProjectOrigin(via: .cli, action: command.name)
            }
            do {
                print(ShotCommand.json(.object(try await ask(request, app: appBundle()))))
            } catch {
                printError("\(program) \(command.name): \(error.message)")
                exit(error.exitCode)
            }
        #if os(Linux)
        case .serve:
            await serveAgents(program: program)
        case let .settings(agentCapture):
            let store = defaultsStore(app: nil)
            if let agentCapture {
                store.set(agentCapture, forKey: PreferenceKey.agentCapture)
                store.synchronize()
            }
            print(ShotCommand.json(.object(["agentCapture": .bool(Preferences(store: store).agentCapture)])))
        #else
        case .serve, .settings:
            let error = ShotCommandError.usage(command.name, "is for Linux; on a Mac, Shot answers agents itself, and Settings › Agents turns that on")
            printError("\(program) \(command.name): \(error.message)")
            exit(error.exitCode)
        #endif
        #if os(macOS)
        case let .record(action):
            var request: AgentRequest
            switch action {
            case let .start(target, duration):
                request = AgentRequest(.record, target: target, duration: duration)
                request.origin = ProjectOrigin(via: .cli, action: command.name)
            case let .stop(id): request = AgentRequest(.stop, id: id)
            case .status: request = AgentRequest(.status)
            case let .mark(label, id): request = AgentRequest(.mark, id: id, label: label)
            case let .run(target, arguments): exit(await record(target, running: arguments, program: program))
            }
            do {
                let result = try await ask(request, app: appBundle())
                print(ShotCommand.json(.object(result)))
                if let path = result["path"]?.string {
                    printError("\(program) frames \"\(path)\" shows what happened in it.")
                } else if case .start = action, let id = result["id"]?.string {
                    printError("Recording. \(program) record --stop \(id) ends it; it stops itself after \(Int(AgentRequest.maximumDuration / 60)) minutes.")
                }
            } catch {
                printError("\(program) \(command.name): \(error.message)")
                exit(error.exitCode)
            }
        case let .pick(options):
            var request = AgentRequest(.pick, duration: options.timeout)
            request.prompt = options.prompt
            request.origin = ProjectOrigin(via: .cli, action: command.name)
            do {
                print(ShotCommand.json(.object(try await ask(request, app: appBundle()))))
            } catch {
                printError("\(program) \(command.name): \(error.message)")
                exit(error.exitCode)
            }
        case let .indexText(folder):
            // One line each time the index is saved, for the app to show what's been read.
            let store = TextIndexStore(bundleID: appBundle()?.bundleIdentifier ?? fallbackSuite)
            do {
                try await store.update(folder: URL(fileURLWithPath: folder, isDirectory: true)) {
                    FileHandle.standardOutput.write(Data("saved\n".utf8))
                }
            } catch {
                printError("\(program) index-text: \(error.localizedDescription)")
                exit(1)
            }
        #endif
        default:
            // On Linux, the commands that capture, record or read video answer that they're not on Linux yet.
            do {
                let projects = ProjectStore(bundleID: appBundle()?.bundleIdentifier ?? fallbackSuite)
                let result = try await ShotCommands.run(command, projects: projects)
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

    /// The tools `shot latest`, `list` and `get` read the captures through, without the app's projects or marks.
    static func captureTools(folder: URL, app: Bundle?) -> AgentTools {
        #if os(macOS)
        AgentTools.live(folder: folder, texts: TextIndexStore(bundleID: app?.bundleIdentifier ?? fallbackSuite))
        #else
        AgentTools.live(folder: folder)
        #endif
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
        #if os(macOS)
        let bundleID = app?.bundleIdentifier ?? fallbackSuite
        let server = AgentTools.live(
            folder: folder, marks: RecordingMarks.url(bundleID: bundleID), projects: ProjectStore(bundleID: bundleID), texts: TextIndexStore(bundleID: bundleID)
        ) { request throws(ShotCommandError) in
            try await ask(request, app: app)
        }.server(version: version)
        #else
        let server = AgentTools.live(folder: folder, projects: ProjectStore(bundleID: fallbackSuite)) { request throws(ShotCommandError) in
            try await ask(request, app: nil)
        }.server(version: version)
        #endif
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

    /// What `shot latest`, `shot list` and `shot get` print, as the MCP tools give it.
    static func readCaptures(_ command: ShotCommand, tools: AgentTools) throws(ShotCommandError) -> JSONValue {
        switch command {
        case let .latest(kind): try tools.latestJSON(kind: kind)
        case let .list(limit, since, query): try tools.listJSON(limit: limit, since: since, query: query, note: printError)
        case let .get(query): try tools.getJSON(query)
        default: throw .internal("\(command.name) doesn't read captures")
        }
    }

    /// What `shot doctor` checks, found without opening Shot: it only asks the app for its status if it's already
    /// answering.
    static func doctorFacts(app: Bundle?) async -> Doctor.Facts {
        let bundleID = app?.bundleIdentifier ?? fallbackSuite
        let socket = AgentSocket.url(bundleID: bundleID)
        let listening = AgentSocket.isListening(at: socket)
        var status: Result<[String: JSONValue], ShotCommandError>?
        if listening {
            do {
                status = .success(try await AgentSocket.send(AgentRequest(.status), to: socket, timeout: .seconds(5)))
            } catch {
                status = .failure(error)
            }
        }
        let folder = captureFolder(app: app)
        let (exists, folderError, captures) = folderFacts(folder)
        return Doctor.Facts(
            bundleID: app?.bundleIdentifier, appPath: app?.bundlePath, version: version(of: app), settingsSuite: fallbackSuite,
            agentCapture: Preferences(store: defaultsStore(app: app)).agentCapture, socketPath: socket.path, listening: listening,
            status: status, folder: folder.path, folderExists: exists, folderError: folderError, captures: captures
        )
    }

    #if !os(macOS)
    /// What `shot doctor` checks on Linux, found without starting `shot serve`: it's only asked for its status if it's
    /// already answering.
    static func linuxDoctorFacts() async -> Doctor.LinuxFacts {
        let socket = AgentSocket.url(bundleID: fallbackSuite)
        let listening = AgentSocket.isListening(at: socket)
        var status: Result<[String: JSONValue], ShotCommandError>?
        if listening {
            do {
                status = .success(try await AgentSocket.send(AgentRequest(.status), to: socket, timeout: .seconds(5)))
            } catch {
                status = .failure(error)
            }
        }
        let folder = captureFolder(app: nil)
        let (exists, folderError, captures) = folderFacts(folder)
        return Doctor.LinuxFacts(
            version: version(of: nil), settingsFile: LinuxSettings.file(suite: fallbackSuite).path,
            sessionType: ProcessInfo.processInfo.environment["XDG_SESSION_TYPE"], agentCapture: Preferences(store: defaultsStore(app: nil)).agentCapture,
            socketPath: socket.path, listening: listening, status: status, folder: folder.path, folderExists: exists, folderError: folderError,
            captures: captures, colorEmoji: PangoShaper.hasColorEmoji, screenshotPortal: LinuxScreen.screenshotPortal()
        )
    }

    /// Answers agents on the socket the app would answer on, until it's stopped, taking screenshots with the session's
    /// capturer. Another `shot serve` already answering leaves this one nothing to do.
    static func serveAgents(program: String) async {
        let daemon = AgentDaemon(
            capturer: LinuxScreen.capturer(), codec: PNGJPEGCodec(), projects: ProjectStore(bundleID: fallbackSuite), version: version(of: nil)
        ) {
            let store = defaultsStore(app: nil)
            Preferences.registerDefaults(in: store)
            return Preferences(store: store)
        }
        let server = AgentSocket.Server(url: AgentSocket.url(bundleID: fallbackSuite)) { request in
            await daemon.handle(request)
        }
        do {
            try server.start()
        } catch {
            printError("\(program) serve: \(error.message)")
            exit(error.exitCode)
        }
        printError("Shot \(version(of: nil)) answering agents at \(server.url.path)")
        // Stopped with ^C or by systemd or pkill, it removes its socket first.
        let stops = [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                server.stop()
                exit(0)
            }
            source.resume()
            return source
        }
        // Reading `stops` keeps their sources alive.
        while !stops.isEmpty {
            try? await Task.sleep(for: .seconds(3600))
        }
    }
    #endif

    /// Whether `folder` is there, why it couldn't be listed if it couldn't, and how many captures it holds.
    static func folderFacts(_ folder: URL) -> (exists: Bool, error: String?, captures: Int) {
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder) && isFolder.boolValue
        guard exists else {
            return (false, nil, 0)
        }
        // macOS's privacy controls let a process see that the folder is there, but can refuse to list it.
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            return (true, nil, Gallery.items(in: folder).count)
        } catch {
            return (true, error.localizedDescription, 0)
        }
    }

    /// How long to wait for the app's answer: a stop or a timed recording waits for the video to be written too.
    static func timeout(for request: AgentRequest) -> Duration {
        switch request.op {
        #if os(Linux)
        // On Wayland, capturing a window opens the desktop's screenshot dialog, which waits for the user.
        case .capture: .seconds(30 + ShotCommand.PickOptions.defaultTimeout + (request.waitStable ?? 0))
        #else
        case .capture: .seconds(30 + (request.waitStable ?? 0))
        #endif
        case .status, .windows, .mark: .seconds(30)
        case .record: .seconds((request.duration ?? 0) + 120)
        case .stop: .seconds(120)
        case .pick: .seconds((request.duration ?? ShotCommand.PickOptions.defaultTimeout) + 30)
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

    /// The settings of a dev build, for a bare `.build/debug/ShotCLI` with no bundle around it, and on Linux the release's.
    static var fallbackSuite: String {
        #if os(macOS)
        ProcessInfo.processInfo.environment["SHOT_DEFAULTS"] ?? "dev.lorcan.Shot.dev"
        #else
        ProcessInfo.processInfo.environment["SHOT_DEFAULTS"] ?? LinuxSettings.suite
        #endif
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
