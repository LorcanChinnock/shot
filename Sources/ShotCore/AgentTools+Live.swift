import Foundation

extension AgentTools {
    /// The tools reading the captures in `folder`, as the gallery lists them. GIFs count as images: an agent sees their
    /// first frame. `marks` is the app's `RecordingMarks` store, whose marks the key frames show, and `projects` its
    /// project store, which keeps what the tools make, and `textIndex` the text the app has read from screenshots, which
    /// `list_captures` searches. Without text recognition, as on Linux, there's no `find_text`. `agent` sends a request to the running app, for the tools that capture. `codec` reads
    /// and writes the images, and they're drawn on `canvasType` canvases; `reader` reads the videos, `assembler` cuts them
    /// and `writer` encodes those it draws.
    public static func live(
        folder: URL,
        marks: URL? = nil,
        projects: ProjectStore? = nil,
        textIndex: @escaping @Sendable () -> TextIndex = { TextIndex() },
        codec: any ImageCoding,
        canvasType: any Canvas.Type,
        reader: any VideoReader,
        assembler: any VideoAssembler,
        writer: any VideoWriter,
        agent: @escaping @Sendable (AgentRequest) async throws(ShotCommandError) -> [String: JSONValue] = { _ throws(ShotCommandError) in throw .unavailable("can't reach Shot from here") }
    ) -> AgentTools {
        var tools = AgentTools(
            folder: folder,
            entries: {
                Gallery.items(in: folder).map { AgentCaptures.Entry(url: $0.url, isVideo: $0.kind == .video, date: $0.date, bytes: $0.bytes, modified: $0.modified) }
            },
            preview: { entry in
                entry.isVideo ? await videoPreview(of: entry.url, codec: codec, reader: reader) : imagePreview(of: entry.url, codec: codec)
            },
            record: { entry in
                entry.isVideo ? nil : codec.record(ofFileAt: entry.url)
            },
            run: { command, origin throws(ShotCommandError) in
                try await ShotCommands.run(command, projects: projects, origin: origin, codec: codec, canvasType: canvasType, reader: reader, assembler: assembler, writer: writer)
            },
            frames: { entry, count throws(ShotCommandError) in
                try await keyFrames(of: entry.url, count: count, marks: marks.map { RecordingMarks.marks(for: entry.url, in: $0) } ?? [], codec: codec, canvasType: canvasType, reader: reader)
            },
            textIndex: textIndex,
            zoom: { entry, rect throws(ShotCommandError) in
                try zoomed(entry.url, rect: rect, codec: codec)
            },
            agent: agent
        )
        #if canImport(CoreGraphics) && canImport(Vision)
        tools.text = { entry throws(ShotCommandError) in
            let read: CaptureText?
            do {
                read = try await TextRecognizer.recognize(fileAt: entry.url, codec: codec)
            } catch {
                throw .internal("Couldn't read the text in \(entry.name): \(error.localizedDescription)")
            }
            guard let read else {
                throw .data("Couldn't read \(entry.name) as an image.")
            }
            return read
        }
        #else
        tools.unavailable = [findText]
        #endif
        return tools
    }

    /// A JPEG small enough for a model, and its size beside the file's when they differ, since the marks Shot records
    /// are in the file's pixels.
    static func imagePreview(of url: URL, codec: any ImageCoding) -> [MCPServer.Content] {
        guard let jpeg = codec.previewJPEG(at: url) else {
            return [.text("Couldn't read \(url.lastPathComponent) as an image.")]
        }
        var content: [MCPServer.Content] = [.image(data: jpeg.base64EncodedString(), mimeType: "image/jpeg")]
        if let file = codec.info(ofFileAt: url)?.size, let shown = codec.info(of: jpeg)?.size, file != shown {
            content.append(.text("The preview is \(shown.width)×\(shown.height) pixels. The file is \(file.width)×\(file.height), which is what the marks' coordinates are in."))
        }
        return content
    }

    /// The part of the image at `url` that `rect` covers, in its pixels, as a JPEG at full resolution unless it's too
    /// big for a model, when it's scaled down as a preview is.
    static func zoomed(_ url: URL, rect: [Double], codec: any ImageCoding) throws(ShotCommandError) -> Zoomed {
        try ShotCommands.requireInput(url)
        guard let image = codec.image(at: url) else {
            throw .data("Couldn't read \(url.lastPathComponent) as an image.")
        }
        guard let region = CropRegion.clamped(rect, width: image.width, height: image.height) else {
            throw .data("rect [\(CropRegion.text(rect).replacingOccurrences(of: ",", with: ", "))] is off \(url.lastPathComponent), which is \(image.width)×\(image.height) pixels.")
        }
        guard let part = image.cropping(to: CGRect(x: region[0], y: region[1], width: region[2], height: region[3])),
              let jpeg = codec.previewJPEG(of: part), let shown = codec.info(of: jpeg)?.size
        else {
            throw .internal("Couldn't draw that part of \(url.lastPathComponent).")
        }
        return Zoomed(
            image: .image(data: jpeg.base64EncodedString(), mimeType: "image/jpeg"), region: region, shown: shown,
            file: CaptureRecord.Size(width: image.width, height: image.height)
        )
    }

    /// The key frames of the recording at `url`, each a line with its time and then a JPEG small enough that a dozen fit
    /// in what clients accept in one result. The frame at each of `marks` comes too, with its label, beside `count`
    /// where the picture changes, fewer of those when they'd go over a dozen in all. What's said in its sound follows the
    /// frame on screen as each phrase starts. Frames are compared on `canvasType` canvases.
    static func keyFrames(
        of url: URL, count: Int, marks: [RecordingMark] = [], codec: any ImageCoding, canvasType: any Canvas.Type, reader: any VideoReader
    ) async throws(ShotCommandError) -> [MCPServer.Content] {
        guard let media = try await ShotCommands.probe(url, reader: reader), media.size != nil else {
            throw .data("Couldn't read \(url.lastPathComponent) as a video.")
        }
        async let heard = narration(of: url, hasAudio: media.hasAudio)
        let limit = ShotCommand.FramesOptions.maximumCount
        let marked = RecordingMark.frames(for: marks, duration: media.duration, limit: limit)
        let keyFrames: [RecordingMark.KeyFrame]
        let frames: [KeyFrameExtractor.Frame]
        do {
            let changes = try await KeyFrameExtractor.changeTimes(in: url, duration: media.duration, count: RecordingMark.changeCount(count, marked: marked.count, limit: limit), canvasType: canvasType, reader: reader)
            keyFrames = RecordingMark.merge(changes: changes, marked: marked)
            frames = try await KeyFrameExtractor.frames(of: url, at: keyFrames.map(\.time), maxWidth: 1024, reader: reader)
        } catch {
            throw ShotCommands.failure(error) { .io("Couldn't read the frames of \(url.lastPathComponent): \($0)") }
        }
        var content: [MCPServer.Content] = []
        let shown = marked.reduce(0) { $0 + $1.labels.count }
        if shown < marks.count {
            content.append(.text("Showing the frames of the first \(shown) of its \(marks.count) marks."))
        }
        let pictures = frames.compactMap { frame in
            codec.previewJPEG(of: frame.image, maxPixelSize: 1024, maxBytes: 400_000).map { (frame: frame, jpeg: $0) }
        }
        let (phrases, note) = await heard
        if let note {
            content.append(.text(note))
        }
        let said = Narration.align(phrases, to: pictures.map(\.frame.time))
        for (index, (frame, jpeg)) in pictures.enumerated() {
            // The frame decoded nearest the time asked for; frames asked for are at least a quarter second apart.
            let labels = keyFrames.min { abs($0.time - frame.time) < abs($1.time - frame.time) }?.labels ?? []
            var line = String(format: "t=%.1fs of %.1fs", frame.time, media.duration)
            if !labels.isEmpty {
                line += ", marked " + labels.map { "\"\($0)\"" }.joined(separator: ", ")
            }
            content.append(.text(line))
            content.append(.image(data: jpeg.base64EncodedString(), mimeType: "image/jpeg"))
            if !said[index].isEmpty {
                content.append(.text(said[index].map(Narration.line).joined(separator: "\n")))
            }
        }
        return content
    }

    /// What's said in the recording at `url`, as phrases to line up with its frames, and a line for the agent about
    /// the transcript, if there's anything to say: that nothing was said, that it was cut short, or why there's none.
    static func narration(of url: URL, hasAudio: Bool) async -> (phrases: [Narration.Phrase], note: String?) {
        guard hasAudio else {
            return ([], nil)
        }
        let words: [Narration.Word]?
        #if canImport(AVFoundation) && canImport(Speech)
        do {
            words = try await SpeechRecognizer.words(in: url)
        } catch {
            return ([], "Couldn't transcribe its sound: \(error.localizedDescription)")
        }
        #else
        words = nil
        #endif
        guard let words else {
            #if canImport(AVFoundation) && canImport(Speech)
            return ([], "Its sound isn't transcribed: that needs macOS 26 and a language with on-device speech recognition.")
            #else
            return ([], "Its sound isn't transcribed: that needs a Mac.")
            #endif
        }
        let phrases = Narration.phrases(words)
        guard !phrases.isEmpty else {
            return ([], "Nothing is said in its sound.")
        }
        let fit = Narration.fitting(phrases)
        var note = "\"Said at\" lines are what's said in its sound, transcribed on this Mac, each after the frame on screen as it starts."
        if fit.left > 0, let last = fit.kept.last {
            note += String(format: " The transcript stops at %.1fs to keep this short, leaving out %d more phrases.", last.end, fit.left)
        }
        return (fit.kept, note)
    }

    /// A frame from early on, where a recording has usually settled, plus how long it runs.
    static func videoPreview(of url: URL, codec: any ImageCoding, reader: any VideoReader) async -> [MCPServer.Content] {
        let media: ImportedMedia
        do {
            guard let probed = try await ShotCommands.probe(url, reader: reader) else {
                return [.text("Couldn't read \(url.lastPathComponent) as a video.")]
            }
            media = probed
        } catch {
            return [.text("Couldn't read \(url.lastPathComponent): \(error.message)")]
        }
        var content: [MCPServer.Content] = []
        let seconds = min(1, media.duration / 2)
        var about = "A recording \(String(format: "%.1f", media.duration)) seconds long"
        if let size = media.size {
            about += ", \(Int(size.width))×\(Int(size.height))"
        }
        about += media.hasAudio ? ", with sound." : ", without sound."
        if media.size != nil {
            var frame: PlatformImage?
            try? await reader.readFrames(of: url, at: [seconds], maxSize: CGSize(width: 1568, height: 1568), tolerance: nil) { frame = try? $0.decoded.get().image }
            if let frame, let jpeg = codec.previewJPEG(of: frame) {
                content.append(.image(data: jpeg.base64EncodedString(), mimeType: "image/jpeg"))
                about += " The image is its frame at \(String(format: "%.1f", seconds)) seconds."
            }
        }
        content.append(.text(about))
        return content
    }
}
