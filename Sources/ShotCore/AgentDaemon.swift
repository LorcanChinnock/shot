import Foundation

/// What `shot serve` answers agents with where there's no app to: the `AgentRequest`s the app takes on a Mac, answered
/// with the same `AgentResponse` fields, through a `ScreenCapturer`. A screenshot is saved to the capture folder, named
/// and written as the app writes an agent's, and isn't copied or shown. One capture runs at a time, as does one
/// recording, so a request for another while one runs is answered `.busy`, though a capture can run beside a
/// recording. A recording is made from the capturer's `RecordingSource`, without sound, as the app records for an
/// agent. Picking isn't here yet, and answers that.
public actor AgentDaemon {
    let capturer: any ScreenCapturer
    let codec: any ImageCoding
    let assembler: any VideoAssembler
    let reader: any VideoReader
    let projects: ProjectStore?
    /// The store of the marks agents stamp on their recordings, which `get_frames` shows.
    let marks: URL?
    let version: String
    /// Read for each request, so a setting changed while it runs counts at once.
    let preferences: @Sendable () -> Preferences
    /// Where recordings keep their segments until they're joined.
    let scratch: URL
    private var capturing = false
    /// Whether a recording is starting, which counts as one under way.
    private var starting = false
    /// The recording in progress, until it's saved or fails.
    private var recording: Recording?
    /// How recordings ended, by ID, so a stop that comes after one stopped itself still gets its answer.
    private var endings: [String: (result: Result<[String: JSONValue], ShotCommandError>, at: Date)] = [:]

    private struct Recording {
        let id: String
        let recorder: SegmentRecorder
        /// The display's name, or the window's app, for messages.
        let name: String
        /// What it records, as the answers give it.
        let window: JSONValue
        /// What the answers say about it, such as that the user picked it.
        let note: String?
        let started: Date
        let origin: ProjectOrigin?
        /// Where it's saved and the name it's saved under, as Settings said when it started.
        let folder: URL
        let prefix: String
        /// The requests waiting for it to end: a timed `record`, and any `stop`.
        var waiters: [CheckedContinuation<Result<[String: JSONValue], ShotCommandError>, Never>] = []
        /// Stops it after its duration, or after `AgentRequest.maximumDuration` at most.
        var limit: Task<Void, Never>?
        /// The moments the agent marked, at the recording's elapsed time, pauses left out.
        var marks: [RecordingMark] = []
        /// Whether it's being stopped and saved, so it can't be marked or stopped again.
        var stopping = false
    }

    public init(
        capturer: any ScreenCapturer, codec: any ImageCoding, assembler: any VideoAssembler, reader: any VideoReader, projects: ProjectStore?, marks: URL? = nil,
        version: String, scratch: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Shot/segments"), preferences: @escaping @Sendable () -> Preferences
    ) {
        self.capturer = capturer
        self.codec = codec
        self.assembler = assembler
        self.reader = reader
        self.projects = projects
        self.marks = marks
        self.version = version
        self.scratch = scratch
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
            return await status()
        case .windows:
            return try await windows()
        case .capture:
            guard !capturing else {
                throw .busy("Shot is in the middle of a capture; try again once it's done.")
            }
            capturing = true
            defer { capturing = false }
            return try await capture(request.target, origin: request.origin, prefs: prefs)
        case .record:
            return try await record(request.target, duration: request.duration, origin: request.origin, prefs: prefs)
        case .stop:
            return try await stop(id: request.id)
        case .mark:
            return try await mark(label: request.label ?? "", id: request.id)
        case .pick:
            throw .notOnLinuxYet
        }
    }

    /// Whether a capture is under way, the recording in progress, if any, and which capturer answers and what it can't
    /// do, for shot doctor.
    private func status() async -> [String: JSONValue] {
        var recorded: JSONValue = .null
        if let recording {
            let elapsed = await recording.recorder.elapsed
            recorded = .object([
                "byAgent": .bool(true), "elapsed": .number((elapsed * 10).rounded() / 10), "id": .string(recording.id), "window": recording.window,
            ])
        }
        return [
            "capturing": .bool(capturing),
            "recording": recorded,
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

    // MARK: Recording

    /// Starts recording the window or display `target` names, or the part of it `target.rect` covers, as that part of
    /// the screen, so whatever covers it shows too, for at most `AgentRequest.maximumDuration`. Answers with the
    /// recording's ID at once, or with `duration`, with the saved recording once it ends.
    private func record(_ target: AgentTarget, duration: Double?, origin: ProjectOrigin?, prefs: Preferences) async throws(ShotCommandError) -> [String: JSONValue] {
        try check(.record)
        guard recording == nil, !starting else {
            throw .busy("Shot is already recording; try again once it's done.")
        }
        starting = true
        defer { starting = false }
        let frameRate = RecordingFrameRate.effective(setting: prefs.recordingFPS, displayRate: RecordingFrameRate.default)
        let source: any RecordingSource, name: String, window: JSONValue
        var note: String?
        // Where windows can't be recorded by themselves, such as on Wayland, the user picks one in the desktop's dialog.
        let rect = target.rect.flatMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
        if target.isWindow, let picked = try capturer.pickedRecordingSource(rect: rect, frameRate: frameRate, showsCursor: prefs.recordShowsCursor) {
            (source, name, window) = (picked, "what was picked", .object(["picked": .bool(true)]))
            note = ScreenCastPortal.pickedNote
        } else {
            let area: CGRect
            (area, name, window) = try await recordedArea(target)
            source = try capturer.recordingSource(area: area, frameRate: frameRate, showsCursor: prefs.recordShowsCursor)
        }
        let recorder: SegmentRecorder
        do {
            recorder = try await SegmentRecorder(source: source, assembler: assembler, scratch: scratch)
        } catch let .unavailable(reason) {
            throw .unavailable(reason)
        } catch {
            throw .io("Couldn't record \(name): \(error.message)")
        }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let started = Date()
        recording = Recording(
            id: id, recorder: recorder, name: name, window: window, note: note, started: started, origin: origin, folder: prefs.captureFolder, prefix: prefs.filePrefix
        )
        let seconds = min(duration ?? AgentRequest.maximumDuration, AgentRequest.maximumDuration)
        recording?.limit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled {
                await self?.end(id)
            }
        }
        guard duration != nil else {
            var fields: [String: JSONValue] = ["id": .string(id), "window": window, "started": .string(ISO8601DateFormatter().string(from: started))]
            if let note {
                fields["note"] = .string(note)
            }
            return fields
        }
        return try await result(id)
    }

    /// Where on screen `target` is, in points, what to call it, and what the answers say it is.
    private func recordedArea(_ target: AgentTarget) async throws(ShotCommandError) -> (area: CGRect, name: String, window: JSONValue) {
        if let number = target.display {
            let displays = try await capturer.displays()
            guard displays.indices.contains(number - 1) else {
                throw .noInput("There's no display \(number); this computer has \(displays.count). shot windows lists them.")
            }
            let display = displays[number - 1]
            guard let area = target.area(in: display.frame) else {
                throw .data("The \(target.rectText) is off display \(number), which is \(Int(display.frame.width))×\(Int(display.frame.height)) points.")
            }
            return (area, display.name, .object(["display": .number(Double(number)), "name": .string(display.name)]))
        }
        try check(.listWindows)
        let windows = try await capturer.windows()
        let candidates = windows.map(\.candidate)
        guard let match = WindowMatch.best(target.window ?? "", bundleID: target.bundleID, in: candidates), let window = windows.first(where: { $0.id == match.id }) else {
            let named = [target.bundleID.map { "of \($0)" }, target.window.map { "matches \"\($0)\"" }].compactMap { $0 }.joined(separator: " ")
            throw .noInput("No open window \(named). \(WindowMatch.listing(candidates))")
        }
        guard let area = target.area(in: window.frame) else {
            throw .data("The \(target.rectText) is off \(match.label), which is \(Int(window.frame.width))×\(Int(window.frame.height)) points.")
        }
        return (area, window.app, .object(["app": .string(window.app), "title": .string(window.title)]))
    }

    /// Stops the recording `id`, or the one in progress, and answers once it's saved. One that has already ended
    /// answers with how it ended.
    private func stop(id: String?) async throws(ShotCommandError) -> [String: JSONValue] {
        pruneEndings()
        if let recording, id == nil || id == recording.id {
            end(recording.id)
            return try await result(recording.id)
        }
        if let id, let ending = endings[id] {
            return try ending.result.get()
        }
        if let id {
            throw .noInput("No agent recording has the id \(id). Finished ones are kept for \(Int(AgentRequest.maximumDuration / 60)) minutes.")
        }
        throw .noInput("No agent recording is in progress. To get one that has already ended, stop it by the id it started with.")
    }

    /// Stops the recording in progress and saves it, answering whoever waits for it, for `shot serve` to end with.
    public func stopRecording() async {
        if let id = recording?.id {
            end(id)
            _ = try? await result(id)
        }
    }

    /// Stamps `label` on the recording `id`, or the one in progress, at its elapsed time, so its key frames show that
    /// moment.
    private func mark(label: String, id: String?) async throws(ShotCommandError) -> [String: JSONValue] {
        guard let recording, id == nil || id == recording.id, !recording.stopping else {
            if let id, endings[id] != nil || recording?.id == id {
                throw .noInput("The agent recording \(id) has ended, so it can't be marked.")
            }
            if let id {
                throw .noInput("No agent recording has the id \(id).")
            }
            throw .noInput("No agent recording is in progress to mark.")
        }
        guard recording.marks.count < RecordingMark.maximumCount else {
            throw .usage(nil, "This recording already has \(RecordingMark.maximumCount) marks, the most it keeps.")
        }
        let elapsed = await recording.recorder.elapsed
        // It may have stopped while the time was read.
        guard self.recording?.id == recording.id, self.recording?.stopping == false else {
            throw .noInput("The agent recording \(recording.id) has ended, so it can't be marked.")
        }
        let mark = RecordingMark(time: (elapsed * 1000).rounded() / 1000, label: String(label.prefix(RecordingMark.maximumLabel)))
        self.recording?.marks.append(mark)
        return ["id": .string(recording.id), "time": .number(mark.time), "label": .string(mark.label)]
    }

    /// Starts stopping and saving the recording `id`, unless it's already stopping.
    private func end(_ id: String) {
        guard let recording, recording.id == id, !recording.stopping else {
            return
        }
        self.recording?.stopping = true
        recording.limit?.cancel()
        Task { await save(id) }
    }

    /// Joins the recording `id` in the capture folder, keeps who asked for it and its marks, and answers whoever waits.
    private func save(_ id: String) async {
        guard let recording, recording.id == id else {
            return
        }
        let url = FileNaming.uniqueURL(in: recording.folder, date: recording.started, pathExtension: "mp4", prefix: recording.prefix)
        let ending: Result<[String: JSONValue], ShotCommandError>
        do {
            do {
                try FileManager.default.createDirectory(at: recording.folder, withIntermediateDirectories: true)
            } catch {
                await recording.recorder.discard()
                throw ShotCommandError.cantCreate("Couldn't save the recording in \(recording.folder.path): \(error.localizedDescription)")
            }
            do {
                _ = try await recording.recorder.stop(to: url)
            } catch {
                throw ShotCommandError.io("The recording failed, and nothing was saved: \(error.message)")
            }
            ending = .success(await savedFields(url, recording))
        } catch {
            ending = .failure(error as? ShotCommandError ?? .internal(error.localizedDescription))
        }
        endings[id] = (ending, Date())
        pruneEndings()
        // Those that asked while it was saved wait on the recording as it is now.
        let waiters = self.recording?.waiters ?? []
        self.recording = nil
        for waiter in waiters {
            waiter.resume(returning: ending)
        }
    }

    /// What a stop answers with for the recording saved at `url`, once it's stamped with its project, which keeps who
    /// asked for it, and its marks are kept.
    private func savedFields(_ url: URL, _ recording: Recording) async -> [String: JSONValue] {
        if let origin = recording.origin, let projects {
            // Dated now, when it's saved, rather than when it was asked for.
            VersionWriter.keep(origin: ProjectOrigin(via: origin.via, client: origin.client, action: origin.action), of: url, id: nil, in: projects)
        }
        let media = try? await MediaProbe.probe(url, reader: reader)
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var fields: [String: JSONValue] = [
            "id": .string(recording.id),
            "path": .string(url.path),
            "bytes": .number(Double(bytes)),
            "duration": .number(((media?.duration ?? 0) * 10).rounded() / 10),
        ]
        if let note = recording.note {
            fields["note"] = .string(note)
        }
        if let size = media?.size {
            fields["size"] = .object(["width": .number(Double(Int(size.width))), "height": .number(Double(Int(size.height)))])
        }
        if !recording.marks.isEmpty {
            fields["marks"] = .array(recording.marks.map { .object(["time": .number($0.time), "label": .string($0.label)]) })
            // Kept before answering, so the key frames the answer leads to show the marks.
            if let marks {
                do {
                    try RecordingMarks.save(recording.marks, for: url, in: marks)
                } catch {
                    Self.log.error("Couldn't keep the marks of \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        return fields
    }

    private static let log = ShotLog.shot("agents")

    /// Waits for the recording `id` to end, and gives how it ended.
    private func result(_ id: String) async throws(ShotCommandError) -> [String: JSONValue] {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<[String: JSONValue], ShotCommandError>, Never>) in
            if recording?.id == id {
                recording?.waiters.append(continuation)
            } else {
                continuation.resume(returning: endings[id]?.result ?? .failure(.noInput("No agent recording has the id \(id).")))
            }
        }
        return try result.get()
    }

    /// Forgets endings older than `AgentRequest.maximumDuration`.
    private func pruneEndings() {
        let cutoff = Date().addingTimeInterval(-AgentRequest.maximumDuration)
        endings = endings.filter { $0.value.at >= cutoff }
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
