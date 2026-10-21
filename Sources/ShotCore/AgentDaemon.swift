import Foundation

/// What `shot serve` answers agents with where there's no app to: the `AgentRequest`s the app takes on a Mac, answered
/// with the same `AgentResponse` fields, through a `ScreenCapturer`. A screenshot is saved to the capture folder, named
/// and written as the app writes an agent's, and isn't copied or shown. One capture runs at a time, so a request that
/// comes while one runs is answered `.busy`. Recording and picking aren't here yet, and answer that.
public actor AgentDaemon {
    let capturer: any ScreenCapturer
    let codec: any ImageCoding
    let projects: ProjectStore?
    let version: String
    /// Read for each request, so a setting changed while it runs counts at once.
    let preferences: @Sendable () -> Preferences
    private var capturing = false

    public init(capturer: any ScreenCapturer, codec: any ImageCoding, projects: ProjectStore?, version: String, preferences: @escaping @Sendable () -> Preferences) {
        self.capturer = capturer
        self.codec = codec
        self.projects = projects
        self.version = version
        self.preferences = preferences
    }

    public func handle(_ request: AgentRequest) async -> AgentResponse {
        do {
            return .success(try await answer(request))
        } catch {
            return .failure(error)
        }
    }

    private func answer(_ request: AgentRequest) async throws(ShotCommandError) -> [String: JSONValue] {
        let prefs = preferences()
        // Status says nothing about the screen, so shot doctor can ask for it with the setting off.
        guard request.op == .status || !request.op.needsAgentCapture || prefs.agentCapture else {
            throw .unavailable(AgentSocket.turnedOff)
        }
        switch request.op {
        case .status:
            return status()
        case .windows:
            return try await windows()
        case .capture:
            guard !capturing else {
                throw .busy("Shot is in the middle of a capture; try again once it's done.")
            }
            capturing = true
            defer { capturing = false }
            return try await capture(request.target, origin: request.origin, prefs: prefs)
        case .record, .stop, .mark, .pick:
            throw .notOnLinuxYet
        }
    }

    /// Whether a capture is under way, and which capturer answers and what it can't do, for shot doctor.
    private func status() -> [String: JSONValue] {
        [
            "capturing": .bool(capturing),
            "recording": .null,
            "version": .string(version),
            "capturer": .string(capturer.name),
            "limits": .object(Dictionary(uniqueKeysWithValues: capturer.limits.map { ($0.key.rawValue, JSONValue.string($0.value)) })),
        ]
    }

    /// The windows, front to back, and the displays, numbered as `display` targets them, as the app lists them.
    private func windows() async throws(ShotCommandError) -> [String: JSONValue] {
        try check(.listWindows)
        let windows = try await capturer.windows().map(\.candidate)
        let displays: [JSONValue] = try await capturer.displays().enumerated().map { index, display in
            .object([
                "display": .number(Double(index + 1)),
                "name": .string(display.name),
                "size": .object(["width": .number(display.frame.width), "height": .number(display.frame.height)]),
                "scale": .number(display.scale),
                "main": .bool(index == 0),
            ])
        }
        // The front window is the one the user is working in.
        var answer: [String: JSONValue] = ["windows": WindowMatch.json(windows, frontmostBundleID: windows.first?.bundleID), "displays": .array(displays)]
        if let note = capturer.windowsNote {
            answer["note"] = .string(note)
        }
        return answer
    }

    /// A screenshot of the window or display `target` names, or the part of it `target.rect` covers.
    private func capture(_ target: AgentTarget, origin: ProjectOrigin?, prefs: Preferences) async throws(ShotCommandError) -> [String: JSONValue] {
        let image: Bitmap
        let frame: CGRect
        var source: CaptureRecord.Source
        let shows: JSONValue
        if let number = target.display {
            try check(target.rect == nil ? .captureDisplay : .captureArea)
            let displays = try await capturer.displays()
            guard displays.indices.contains(number - 1) else {
                throw .noInput("There's no display \(number); this computer has \(displays.count). shot windows lists them.")
            }
            let display = displays[number - 1]
            guard let area = target.area(in: display.frame) else {
                throw .data("The \(target.rectText) is off display \(number), which is \(Int(display.frame.width))×\(Int(display.frame.height)) points.")
            }
            image = try await settled(within: target.waitStable) { () throws(ShotCommandError) in
                if target.rect == nil {
                    try await capturer.capture(display: display)
                } else {
                    try await capturer.capture(area: area)
                }
            }
            frame = area
            source = CaptureRecord.Source(mode: "fullscreen")
            shows = .object(["display": .number(Double(number)), "name": .string(display.name)])
        } else {
            try check(.listWindows)
            try check(.captureWindow)
            let windows = try await capturer.windows()
            let candidates = windows.map(\.candidate)
            let match = WindowMatch.best(target.window ?? "", bundleID: target.bundleID, in: candidates)
            // Where windows can't all be found, such as on Wayland, the user picks one in the desktop's dialog instead.
            if match == nil, let picked = try await capturer.capturePicked() {
                return try saveFields(picked: picked, target: target, origin: origin, prefs: prefs)
            }
            guard let match, let window = windows.first(where: { $0.id == match.id }) else {
                let named = [target.bundleID.map { "of \($0)" }, target.window.map { "matches \"\($0)\"" }].compactMap { $0 }.joined(separator: " ")
                throw .noInput("No open window \(named). \(WindowMatch.listing(candidates))")
            }
            let captured = try await settled(within: target.waitStable) { () throws(ShotCommandError) in
                try await capturer.capture(window: window)
            }
            guard let area = target.area(in: window.frame),
                  let pixels = target.pixels(width: captured.width, height: captured.height, scale: captured.scale),
                  let cropped = captured.cropped(to: pixels)
            else {
                throw .data("The \(target.rectText) is off \(match.label), which is \(Int(window.frame.width))×\(Int(window.frame.height)) points.")
            }
            image = cropped
            frame = area
            source = CaptureRecord.Source(mode: "window", app: window.app, bundleID: window.appID.isEmpty ? nil : window.appID, windowTitle: window.title)
            shows = .object(["app": .string(window.app), "title": .string(window.title)])
        }
        source.screenFrame = CaptureRecord.Frame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        return try saveFields(image, source: source, shows: shows, origin: origin, prefs: prefs)
    }

    /// Saves what the user picked in the desktop's dialog, or the part of it `target.rect` covers, saying it was picked,
    /// since it may not be the window asked for. Where on screen it was isn't known, nor is waiting for it to settle.
    private func saveFields(picked: Bitmap, target: AgentTarget, origin: ProjectOrigin?, prefs: Preferences) throws(ShotCommandError) -> [String: JSONValue] {
        guard let pixels = target.pixels(width: picked.width, height: picked.height, scale: picked.scale), let image = picked.cropped(to: pixels) else {
            let width = Int(Double(picked.width) / picked.scale), height = Int(Double(picked.height) / picked.scale)
            throw .data("The \(target.rectText) is off what was picked, which is \(width)×\(height) points.")
        }
        var fields = try saveFields(image, source: CaptureRecord.Source(mode: "area"), shows: .object(["picked": .bool(true)]), origin: origin, prefs: prefs)
        fields["note"] = .string(ScreenshotPortal.pickedNote)
        return fields
    }

    private func saveFields(_ image: Bitmap, source: CaptureRecord.Source, shows: JSONValue, origin: ProjectOrigin?, prefs: Preferences) throws(ShotCommandError) -> [String: JSONValue] {
        let (url, width, height) = try save(image, source: source, origin: origin, prefs: prefs)
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return [
            "path": .string(url.path),
            "size": .object(["width": .number(Double(width)), "height": .number(Double(height))]),
            "bytes": .number(Double(bytes)),
            "window": shows,
        ]
    }

    /// Refuses what the capturer says it can't do in this session, with its reason.
    private func check(_ capability: ScreenCapability) throws(ShotCommandError) {
        if let reason = capturer.limits[capability] {
            throw .unavailable(reason)
        }
    }

    /// What `capture` gives once the picture stops changing, taking it a few times a second for up to `timeout`
    /// seconds, or at once without one, as the app waits.
    private func settled(within timeout: Double?, _ capture: () async throws(ShotCommandError) -> Bitmap) async throws(ShotCommandError) -> Bitmap {
        var shot = try await capture()
        guard let timeout else {
            return shot
        }
        var wait = StableWait(timeout: timeout)
        let start = ContinuousClock.now
        func elapsed() -> Double {
            let time = (ContinuousClock.now - start).components
            return Double(time.seconds) + Double(time.attoseconds) / 1e18
        }
        while wait.add(shot.grayThumbnail, elapsed: elapsed()) == .wait {
            try? await Task.sleep(for: .seconds(StableWait.interval))
            shot = try await capture()
        }
        return shot
    }

    /// Writes the screenshot to the capture folder as the app writes an agent's: downscaled to points if Settings ask,
    /// in the format and with the prefix they give, its record inside, and who asked kept in the project store.
    private func save(_ captured: Bitmap, source: CaptureRecord.Source, origin: ProjectOrigin?, prefs: Preferences) throws(ShotCommandError) -> (url: URL, width: Int, height: Int) {
        var image = captured
        if prefs.downscaleRetina, image.scale > 1 {
            image = image.scaledDown(toFit: Int((Double(max(image.width, image.height)) / image.scale).rounded()))
            image.scale = 1
        }
        let record = CaptureRecord(kind: "image", created: Date(), size: CaptureRecord.Size(width: image.width, height: image.height), scale: image.scale, source: source)
        let projectID = origin == nil ? nil : ProjectKey.newID()
        let format = prefs.imageFormat
        guard let data = codec.encode(image, as: format, quality: 0.9, metadata: ImageMetadata(record: record, projectID: projectID)) else {
            throw .internal("Couldn't encode the screenshot as \(format.fileExtension.uppercased()).")
        }
        let folder = prefs.captureFolder, prefix = prefs.filePrefix
        let url: URL
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = try FileNaming.writeNew(data, in: folder) {
                FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: format.fileExtension, prefix: prefix)
            }
        } catch {
            throw .cantCreate("Couldn't save the screenshot in \(folder.path): \(error.localizedDescription)")
        }
        if let origin, let projects {
            // Dated now, when it's saved, rather than when it was asked for.
            VersionWriter.keep(origin: ProjectOrigin(via: origin.via, client: origin.client, action: origin.action), of: url, id: projectID, in: projects)
        }
        return (url, image.width, image.height)
    }
}
