#if canImport(AVFoundation) && canImport(CoreGraphics)
import AVFoundation
import CoreGraphics
import Foundation

/// Runs the `shot` media commands with no window, display or permission, for the command line and the MCP tools. Each
/// writes a new file and never touches its input: the result goes beside the input as its next version unless an output
/// that doesn't exist yet is named, and it's moved into place in one step that fails rather than replace anything.
/// What `annotate`, `redact`, `crop`, `trim` and `gif` write keeps its project, as the editors' Save, Save Copy and
/// Export do, so it reopens live in Shot.
public enum ShotCommands {
    /// The JSON a command prints: at least `path`, `size` and `bytes` for what it wrote, or what `info` found. The files
    /// it writes keep their projects in `projects`, saying `origin` made them, by default the command line running
    /// `command`. With no store, they keep none. `codec` reads and writes the images, and they're drawn on `canvasType` canvases;
    /// `reader` reads the videos and `assembler` cuts them.
    public static func run(
        _ command: ShotCommand, projects: ProjectStore? = nil, origin: ProjectOrigin? = nil, codec: any ImageCoding, canvasType: any Canvas.Type,
        reader: any VideoReader, assembler: any VideoAssembler
    ) async throws(ShotCommandError) -> JSONValue {
        let origin = origin ?? ProjectOrigin(via: .cli, action: command.name)
        switch command {
        case let .info(path):
            return try await info(url(path), codec: codec, reader: reader)
        case let .gif(options):
            return try await gif(options, projects: projects, origin: origin, codec: codec, canvasType: canvasType, reader: reader, assembler: assembler)
        case let .trim(options):
            return try await trim(options, projects: projects, origin: origin, codec: codec, canvasType: canvasType, reader: reader, assembler: assembler)
        case let .redact(options):
            return try await redact(options, projects: projects, origin: origin, codec: codec, canvasType: canvasType)
        case let .annotate(options):
            let marks: [CaptureMark]
            switch options.marks {
            case let .marks(given):
                marks = given
            case let .file(path):
                let file = url(path)
                guard let data = try? Data(contentsOf: file) else {
                    throw FileManager.default.fileExists(atPath: file.path) ? .io("couldn't read \(path)") : .noInput("\(path) doesn't exist")
                }
                marks = try CaptureMark.list(from: data)
            case .standardInput:
                marks = try CaptureMark.list(from: FileHandle.standardInput.readDataToEndOfFile())
            }
            return try draw(input: options.input, output: options.output, edit: ImageEdit(marks: marks), projects: projects, origin: origin, codec: codec, canvasType: canvasType) { (_: CGImage) in [] }
        case let .frames(options):
            return try await frames(options, codec: codec, reader: reader)
        case let .text(path):
            return try await text(url(path), codec: codec)
        case let .diff(options):
            return try diff(options, codec: codec, canvasType: canvasType)
        case let .crop(options):
            return try draw(input: options.input, output: options.output, edit: ImageEdit(crop: options.rect), cropField: "rect", projects: projects, origin: origin, codec: codec, canvasType: canvasType) { (_: CGImage) in [] }
        case let .edit(options):
            return try await edit(options, projects: projects, origin: origin, codec: codec, canvasType: canvasType, reader: reader, assembler: assembler)
        case .capture, .record, .watch, .pick, .windows, .latest, .list, .get, .doctor, .mcp, .indexText, .version, .help:
            throw .internal("\(command.name) isn't a media command")
        }
    }

    // MARK: Commands

    static func info(_ url: URL, codec: any ImageCoding, reader: any VideoReader) async throws(ShotCommandError) -> JSONValue {
        try requireInput(url)
        var object: [String: JSONValue] = ["path": .string(url.path), "bytes": .number(Double(bytes(of: url)))]
        if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
            object["created"] = .string(ISO8601DateFormatter().string(from: created))
        }
        if let image = codec.info(ofFileAt: url), let size = image.size {
            object["kind"] = .string(image.isGIF ? "gif" : "image")
            object["size"] = json(size)
            object["scale"] = .number(Double(codec.scale(ofFileAt: url)))
            if image.frames > 1 {
                object["frames"] = .number(Double(image.frames))
            }
            if let record = codec.record(ofFileAt: url), let data = try? record.encoded(),
               let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                object["record"] = value
            }
            return .object(object)
        }
        guard let media = try? await MediaProbe.probe(url, reader: reader) else {
            throw .data("\(url.lastPathComponent) isn't an image or video Shot can read")
        }
        object["kind"] = .string(media.size == nil ? "audio" : "video")
        object["duration"] = .number((media.duration * 1000).rounded() / 1000)
        object["hasAudio"] = .bool(media.hasAudio)
        if let size = media.size {
            object["size"] = .object(["width": .number(Double(Int(size.width))), "height": .number(Double(Int(size.height)))])
        }
        return .object(object)
    }

    /// Writes the part of the video in the range as a GIF, as the video editor's Export does: an edit with only `keep`,
    /// as a GIF. It keeps the trim as its project, so Edit on it opens the video trimmed.
    static func gif(
        _ options: ShotCommand.GIFOptions, projects: ProjectStore?, origin: ProjectOrigin, codec: any ImageCoding, canvasType: any Canvas.Type,
        reader: any VideoReader, assembler: any VideoAssembler
    ) async throws(ShotCommandError) -> JSONValue {
        let media = try await video(url(options.input), reader: reader)
        _ = try trimmed(media, start: options.start, end: options.end, command: "gif")
        let edit = VideoEdit(keep: [[options.start ?? 0, min(options.end ?? media.duration, media.duration)]], format: .gif, fps: options.fps, width: options.width)
        let result = try await editVideo(edit, input: options.input, output: options.output, extensions: ["gif"], command: "gif", projects: projects, origin: origin, codec: codec, canvasType: canvasType, reader: reader, assembler: assembler)
        guard case var .object(object) = result else {
            return result
        }
        // gif prints what it always has; the frame rate is its own.
        object["fps"] = nil
        return .object(object)
    }

    /// Writes the part of the video in the range as a new file, as the video editor's Save Copy does: an edit with only
    /// `keep`. It keeps the trim as its project, so it opens in the video editor with the rest of the recording still
    /// there to drag back.
    static func trim(
        _ options: ShotCommand.TrimOptions, projects: ProjectStore?, origin: ProjectOrigin, codec: any ImageCoding, canvasType: any Canvas.Type,
        reader: any VideoReader, assembler: any VideoAssembler
    ) async throws(ShotCommandError) -> JSONValue {
        let input = url(options.input)
        let media = try await video(input, reader: reader)
        _ = try trimmed(media, start: options.start, end: options.end, command: "trim")
        let own = input.pathExtension.lowercased()
        let edit = VideoEdit(keep: [[options.start, min(options.end, media.duration)]], format: ["mov", "mp4"].contains(own) || options.output != nil ? nil : .mov)
        return try await editVideo(edit, input: options.input, output: options.output, extensions: ["mov", "mp4"], command: "trim", projects: projects, origin: origin, codec: codec, canvasType: canvasType, reader: reader, assembler: assembler)
    }

    /// Hides the rects, and with `detect` the private text read in the image, as blurs or pixelations the new version
    /// records, so they stay live layers in Shot. With nothing to hide, it writes nothing and gives the input's path.
    static func redact(_ options: ShotCommand.RedactOptions, projects: ProjectStore?, origin: ProjectOrigin, codec: any ImageCoding, canvasType: any Canvas.Type) async throws(ShotCommandError) -> JSONValue {
        var found: [CaptureText.Found] = []
        if !options.detect.isEmpty {
            let input = url(options.input)
            try requireInput(input)
            guard let image = codec.image(at: input) else {
                throw .data("\(input.lastPathComponent) isn't an image Shot can read")
            }
            do {
                found = try await TextRecognizer.recognize(image).toHide(options.detect)
            } catch {
                throw .internal("couldn't read the text in \(input.lastPathComponent): \(error.localizedDescription)")
            }
            if found.isEmpty, options.rects.isEmpty {
                var object = try written(input, codec: codec)
                object["found"] = CaptureText.json(hidden: [])
                object["unchanged"] = .bool(true)
                return .object(object)
            }
        }
        let result = try draw(input: options.input, output: options.output, projects: projects, origin: origin, codec: codec, canvasType: canvasType) { (image: CGImage) throws(ShotCommandError) in
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            var rects: [CGRect] = []
            for (index, r) in options.rects.enumerated() {
                let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3]).intersection(bounds)
                guard !rect.isNull, rect.width >= 1, rect.height >= 1 else {
                    throw .data("rect \(index + 1) (\(r.map { String(format: "%g", $0) }.joined(separator: ","))) is off the \(image.width)×\(image.height) image")
                }
                rects.append(rect)
            }
            return (rects + found.map(\.box)).map { rect in
                let kind: Annotation.Kind = options.style == .blur ? .blur(rect) : .pixelate(rect)
                return Annotation(kind: kind, color: RGBA.presets[0], lineWidth: EditorStyle.widths[1])
            }
        }
        guard !options.detect.isEmpty, case var .object(object) = result else {
            return result
        }
        object["found"] = CaptureText.json(hidden: found)
        return .object(object)
    }

    static func frames(_ options: ShotCommand.FramesOptions, codec: any ImageCoding, reader: any VideoReader) async throws(ShotCommandError) -> JSONValue {
        let input = url(options.input)
        let duration = try await video(input, reader: reader).duration
        let times: [Double]
        if let every = options.every {
            times = Array(stride(from: 0, to: duration, by: every))
            guard times.count <= ShotCommand.FramesOptions.maximumEvery else {
                throw .usage("frames", "--every \(String(format: "%g", every)) gives \(times.count) frames of the \(String(format: "%.1f", duration)) s video; the most is \(ShotCommand.FramesOptions.maximumEvery)")
            }
        } else {
            do {
                times = try await KeyFrameExtractor.changeTimes(in: input, duration: duration, count: options.count, reader: reader)
            } catch {
                throw .io("couldn't read the video's frames: \(error.localizedDescription)")
            }
        }
        let folder = try makeFolder(beside: input, output: options.output)
        do {
            let frames = try await KeyFrameExtractor.frames(of: input, at: times, maxWidth: options.width, reader: reader)
            var written: [JSONValue] = []
            for (index, frame) in frames.enumerated() {
                let file = folder.appendingPathComponent(String(format: "%02d %.1fs.jpg", index + 1, frame.time))
                guard let data = codec.data(from: frame.image, scale: 1, format: .jpeg) else {
                    throw ShotCommandError.internal("couldn't encode the frame at \(String(format: "%.1f", frame.time)) s")
                }
                try data.write(to: file, options: .withoutOverwriting)
                var object = try Self.written(file, codec: codec)
                object["time"] = .number((frame.time * 1000).rounded() / 1000)
                written.append(.object(object))
            }
            return .object(["path": .string(folder.path), "frames": .array(written)])
        } catch {
            // The folder is new and only this command's, so a failure leaves nothing behind.
            try? FileManager.default.removeItem(at: folder)
            throw (error as? ShotCommandError) ?? .io("couldn't write the frames: \(error.localizedDescription)")
        }
    }

    static func text(_ url: URL, codec: any ImageCoding) async throws(ShotCommandError) -> JSONValue {
        try requireInput(url)
        guard let image = codec.image(at: url) else {
            throw .data("\(url.lastPathComponent) isn't an image Shot can read")
        }
        do {
            var object = try await TextRecognizer.recognize(image).json(words: true)
            object["path"] = .string(url.path)
            return .object(object)
        } catch {
            throw .internal("couldn't read the text in \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// A new folder for `frames`: `output` if given, which must not exist, or `<name> frames` beside the video, as its
    /// next version when that's taken. Creating it fails if it exists, so it's never one already in use.
    static func makeFolder(beside input: URL, output: String?) throws(ShotCommandError) -> URL {
        var folder = output.map(url) ?? input.deletingPathExtension().deletingLastPathComponent().appendingPathComponent(input.deletingPathExtension().lastPathComponent + " frames")
        for _ in 0 ..< 1000 {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                return folder
            } catch CocoaError.fileWriteFileExists where output == nil {
                folder = VersionNaming.nextVersionURL(of: folder)
            } catch CocoaError.fileWriteFileExists {
                throw .cantCreate("\(folder.path) already exists, and shot never overwrites")
            } catch {
                throw .cantCreate("couldn't make \(folder.path): \(error.localizedDescription)")
            }
        }
        throw .cantCreate("couldn't find a free name beside \(input.path)")
    }

    /// Draws the annotations `make` gives for the input image, in its pixels, and the image's scale, onto a copy of it,
    /// with `edit`'s changes, as the image editor's Save does. A version is drawn on again from its original with its
    /// layers, which stay live with the new marks on top, rather than having them baked in. The new file records the marks
    /// for agents and keeps them in `projects`, so a person can open it in Shot and change them; unlike the editor, a
    /// command records whether or not agents are handed captures. `edit`'s crop, called `cropField` in messages, keeps that
    /// part, as the editor's crop does, so the version opens with it still adjustable. One scaled to 1× keeps no layers,
    /// since its pixels are no longer theirs. `layers` adds the new version's layers, each with its id and type.
    static func draw(
        input path: String, output: String?, edit: ImageEdit = ImageEdit(), cropField: String = "crop", layers: Bool = false,
        projects: ProjectStore?, origin: ProjectOrigin, codec: any ImageCoding, canvasType: any Canvas.Type, _ make: (CGImage, CGFloat) throws(ShotCommandError) -> [Annotation]
    ) throws(ShotCommandError) -> JSONValue {
        let input = url(path)
        try requireInput(input)
        guard let image = codec.image(at: input) else {
            throw .data("\(input.lastPathComponent) isn't an image Shot can read")
        }
        let own = input.pathExtension.lowercased()
        let asked = edit.format.map { $0 == .png ? "png" : "jpg" }
        let target = try destination(for: input, output: output, extensions: ["png", "jpg", "jpeg"], default: asked ?? (["png", "jpg", "jpeg"].contains(own) ? own : "png"), command: "draw")
        let format = ImageFormat(fileExtension: target.url.pathExtension)
        if let asked, ImageFormat(fileExtension: asked) != format, let output {
            throw .usage(nil, "-o \(output) isn't a \(asked == "png" ? "PNG" : "JPEG"), the format the edit asks for")
        }
        if format == .jpeg, edit.background?.lowercased() == "none" {
            throw .data("background none needs a PNG: a JPEG has no transparency")
        }
        var placed: [PlacedImageFile] = []
        for (index, placement) in edit.place.enumerated() {
            let file = url(placement.path)
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw .noInput("place[\(index)]: \(file.path) doesn't exist")
            }
            guard let picture = codec.image(at: file) else {
                throw .data("place[\(index)]: \(file.lastPathComponent) isn't an image Shot can read")
            }
            placed.append(PlacedImageFile(image: picture, scale: codec.scale(ofFileAt: file)))
        }
        let scale = codec.scale(ofFileAt: input)
        let drawn = try make(image, scale)
        var document = EditorDocument(base: image, background: EditorDocument.defaultBackground(for: format))
        var original = input
        if let saved = VersionWriter.savedLayers(of: input, in: projects, codec: codec) {
            var reopened = EditorDocument(base: saved.image)
            reopened.restore(saved.layers)
            // Only while the version is still the size its layers draw, so its pixels are theirs.
            if reopened.canvasRect.size == CGSize(width: image.width, height: image.height) {
                document = reopened
                original = saved.original
            }
        }
        document.hasWindowShadow = codec.hasWindowShadow(ofFileAt: original)
        try document.apply(edit, drawn: drawn, placed: placed, scale: scale, name: input.lastPathComponent, cropField: cropField, shaper: canvasType.shaper)
        if format == .jpeg {
            // JPEG has no alpha, as the editor's background picker knows.
            if document.background == nil {
                document.background = EditorDocument.defaultBackground(for: format)
            }
            document.background?.a = 1
        }
        let oneX = edit.isOneX && scale > 1
        defer { AnnotationRenderer.releaseCaches() }
        let projectID = projects == nil ? nil : ProjectKey.newID()
        let rendered: VersionWriter.RenderedImage
        do throws(VersionWriter.Failure) {
            let record = VersionWriter.record(of: document, drawnOn: original, savedAs: format, scale: scale, atOneX: oneX, codec: codec, shaper: canvasType.shaper)
            rendered = try VersionWriter.render(document, scale: scale, as: format, record: record, projectID: projectID, atOneX: oneX, codec: codec, canvasType: canvasType)
        } catch .draw {
            throw .internal("couldn't draw the image")
        } catch {
            throw .internal("couldn't encode the image")
        }
        let temporary = temporaryURL(beside: target.url, pathExtension: target.url.pathExtension)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try rendered.file.write(to: temporary, options: .withoutOverwriting)
        } catch {
            throw .cantCreate("couldn't write in \(temporary.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        let placedAt = try place(temporary, at: target)
        if oneX {
            if let projects {
                VersionWriter.keep(origin: origin, of: placedAt, id: projectID, in: projects)
            }
        } else {
            VersionWriter.keep(document.snapshot, of: placedAt, id: projectID, original: original, in: projects, origin: origin)
        }
        var object = try written(placedAt, codec: codec)
        if layers {
            object["layers"] = .array((rendered.record?.annotations ?? []).map { mark in
                .object(["id": .string(mark.id ?? ""), "type": .string(mark.type)])
            })
        }
        return .object(object)
    }

    /// The same for `redact`, which needs only the image.
    static func draw(
        input path: String, output: String?, edit: ImageEdit = ImageEdit(), cropField: String = "crop", projects: ProjectStore?, origin: ProjectOrigin,
        codec: any ImageCoding, canvasType: any Canvas.Type, _ make: (CGImage) throws(ShotCommandError) -> [Annotation]
    ) throws(ShotCommandError) -> JSONValue {
        try draw(input: path, output: output, edit: edit, cropField: cropField, projects: projects, origin: origin, codec: codec, canvasType: canvasType) { (image: CGImage, _: CGFloat) throws(ShotCommandError) in try make(image) }
    }

    /// Makes the edit's changes to the image, as `draw` does, and lists the new version's layers, so an agent can
    /// remove one later by its id; or to the video, as `editVideo` does. An edit read from JSON is an image's or a
    /// video's by what the input is.
    static func edit(
        _ options: ShotCommand.EditOptions, projects: ProjectStore?, origin: ProjectOrigin, codec: any ImageCoding, canvasType: any Canvas.Type,
        reader: any VideoReader, assembler: any VideoAssembler
    ) async throws(ShotCommandError) -> JSONValue {
        let data: Data
        switch options.spec {
        case let .edit(edit):
            return try draw(input: options.input, output: options.output, edit: edit, layers: true, projects: projects, origin: origin, codec: codec, canvasType: canvasType) { (_: CGImage, _: CGFloat) in [] }
        case let .video(edit):
            return try await editVideo(edit, input: options.input, output: options.output, projects: projects, origin: origin, codec: codec, canvasType: canvasType, reader: reader, assembler: assembler)
        case let .json(text):
            data = Data(text.utf8)
        case let .file(path):
            let file = url(path)
            guard let read = try? Data(contentsOf: file) else {
                throw FileManager.default.fileExists(atPath: file.path) ? .io("couldn't read \(path)") : .noInput("\(path) doesn't exist")
            }
            data = read
        case .standardInput:
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        let input = url(options.input)
        try requireInput(input)
        if isImage(input, codec: codec) {
            return try draw(input: options.input, output: options.output, edit: ImageEdit.parse(data), layers: true, projects: projects, origin: origin, codec: codec, canvasType: canvasType) { (_: CGImage, _: CGFloat) in [] }
        }
        return try await editVideo(VideoEdit.parse(data), input: options.input, output: options.output, projects: projects, origin: origin, codec: codec, canvasType: canvasType, reader: reader, assembler: assembler)
    }

    /// Whether the file is an image `codec` reads, rather than a video.
    static func isImage(_ url: URL, codec: any ImageCoding) -> Bool {
        codec.info(ofFileAt: url) != nil
    }

    /// Makes the edit's changes to the video, as the video editor and its export do, and writes it as a new file beside
    /// it that keeps the edit as its project, so it opens in the video editor live. A video that's an earlier edit is
    /// edited again from its project, so its marks stay live, while it still plays as its project does. With `maxBytes`,
    /// a GIF steps down its frame rate and width, and an MP4 or MOV its size, until the file fits.
    /// `extensions` are the outputs `command` can write.
    static func editVideo(
        _ edit: VideoEdit, input path: String, output: String?, extensions: [String] = ["mp4", "mov", "gif"], command: String = "edit",
        projects: ProjectStore?, origin: ProjectOrigin, codec: any ImageCoding, canvasType: any Canvas.Type, reader: any VideoReader, assembler: any VideoAssembler
    ) async throws(ShotCommandError) -> JSONValue {
        let input = url(path)
        let media = try await video(input, reader: reader)
        guard let size = media.size else {
            throw .internal("couldn't read the video's size")
        }
        var base = Project(source: media.source, duration: media.duration, canvasSize: size, hasAudio: media.hasAudio)
        var original = input
        // A frame crop is the whole of the file, so it's taken into the canvas first: the edit's crop and marks are in
        // the file's pixels.
        if let projects, let reopened = VersionWriter.project(of: input, in: projects),
           abs(reopened.project.duration - media.duration) < 0.05,
           let framed = reopened.project.frameCrop == nil ? reopened.project : reopened.project.reframed(to: reopened.project.outputRect, shaper: canvasType.shaper),
           framed.canvasSize == size {
            base = framed
            original = reopened.original
        }
        var appended: [ImportedMedia] = []
        for (index, name) in edit.append.enumerated() {
            let file = url(name)
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw .noInput("append[\(index)]: \(file.path) doesn't exist")
            }
            guard let clip = try? await MediaProbe.probe(file, reader: reader), clip.size != nil else {
                throw .data("append[\(index)]: \(file.lastPathComponent) isn't a video Shot can read")
            }
            appended.append(clip)
        }
        let project = try base.applying(edit, appended: appended, shaper: canvasType.shaper)

        let own = input.pathExtension.lowercased()
        let asked = edit.format?.rawValue
        let target = try destination(for: input, output: output, extensions: extensions, default: asked ?? (["mov", "mp4"].contains(own) ? own : "mp4"), command: command)
        let ext = target.url.pathExtension.lowercased()
        if let asked, asked != ext, let output {
            throw .usage(command, "-o \(output) isn't a .\(asked), the format the edit asks for")
        }
        let speed = edit.speed ?? 1
        let canvasWidth = Int(project.outputRect.width)
        let temporary = temporaryURL(beside: target.url, pathExtension: ext)
        defer { try? FileManager.default.removeItem(at: temporary) }

        var written: (plan: VideoExportPlan, kept: Project, outcome: VideoExportPlan.Outcome, fps: Double?, width: Int?, scale: Double?)
        if ext == "gif" {
            let asked = edit.width ?? 720
            let start = SizeFit.GIFStep(fps: edit.fps ?? 12, width: asked == 0 ? canvasWidth : min(asked, canvasWidth))
            let steps = edit.maxBytes == nil ? [start] : SizeFit.gifSteps(fps: start.fps, width: start.width)
            let plans = steps.map { step in (step, gifPlan(project, fps: step.fps, width: step.width, canvasWidth: canvasWidth, speed: speed)) }
            let result = try await fit(plans, maxBytes: edit.maxBytes, to: temporary, canvasType: canvasType, reader: reader, assembler: assembler, describe: { "\(String(format: "%g", $0.fps)) fps and \($0.width) px wide" })
            written = (result.plan, project, result.outcome, result.step.fps, result.step.width, nil)
        } else {
            let fileType: AVFileType = ext == "mov" ? .mov : .mp4
            var plans: [((scale: Double, kept: Project), VideoExportPlan)] = []
            for scale in edit.maxBytes == nil ? [1] : SizeFit.videoScales {
                let made = try videoPlan(project, scale: scale, speed: speed, muted: edit.mute, fileType: fileType, shaper: canvasType.shaper)
                plans.append(((scale, made.kept), made.plan))
            }
            let result = try await fit(plans, maxBytes: edit.maxBytes, to: temporary, canvasType: canvasType, reader: reader, assembler: assembler, describe: { "\(Int(($0.scale * 100).rounded()))% of its size" })
            written = (result.plan, result.step.kept, result.outcome, nil, nil, edit.maxBytes == nil ? nil : result.step.scale)
        }
        let placed = try place(temporary, at: target)
        VersionWriter.keep(written.kept, of: placed, original: original, in: projects, origin: origin)
        var object = try Self.written(placed, codec: codec)
        if let probed = try? await MediaProbe.probe(placed, reader: reader) {
            object["duration"] = .number((probed.duration * 1000).rounded() / 1000)
            if let size = probed.size {
                object["size"] = .object(["width": .number(Double(Int(size.width))), "height": .number(Double(Int(size.height)))])
            }
        }
        if let frames = written.outcome.frameCount {
            object["frames"] = .number(Double(frames))
            object["truncated"] = .bool(written.outcome.truncated)
        }
        if let fps = written.fps {
            object["fps"] = .number(fps)
        }
        if let scale = written.scale {
            object["scale"] = .number(scale)
        }
        return .object(object)
    }

    /// A GIF of `project`, as the editor's Export writes one, at most `width` wide.
    static func gifPlan(_ project: Project, fps: Double, width: Int, canvasWidth: Int, speed: Double) -> VideoExportPlan {
        let maxWidth: CGFloat? = width >= canvasWidth ? nil : CGFloat(width)
        guard let trim = project.trimEdit else {
            return .compositeGIF(project, fps: fps, maxWidth: maxWidth, speed: speed)
        }
        return .trimmedGIF(source: trim.source, range: trim.range, cuts: trim.cuts, fps: fps, maxWidth: maxWidth, speed: speed)
    }

    /// An MP4 or MOV of `project`, as the editor's Export writes one: cut from the recording when it's only kept or cut,
    /// else drawn, at `scale` of its canvas. A drawn video plays at its own speed, as Export's does. `kept` is the project
    /// the file keeps, with its sound, as Export keeps it whether or not the file has any.
    static func videoPlan(_ project: Project, scale: Double, speed: Double, muted: Bool, fileType: AVFileType, shaper: any TextShaper) throws(ShotCommandError) -> (plan: VideoExportPlan, kept: Project) {
        if scale == 1, let trim = project.trimEdit {
            return (.trimmed(source: trim.source, range: trim.range, cuts: trim.cuts, speed: speed, muted: muted, fileType: fileType), project)
        }
        guard speed == 1 else {
            throw .data("speed changes only a GIF, or a video that's only kept or cut, as the video editor's export does; take speed out, or make a GIF")
        }
        guard let sized = scale == 1 ? project : project.reframed(to: CGRect(origin: .zero, size: project.canvasSize), scale: CGFloat(scale), shaper: shaper) else {
            throw .data("maxBytes: the video has clips or marks that move or scale over time, so it can't be drawn smaller")
        }
        var drawn = sized
        if muted {
            for index in drawn.tracks.indices where drawn.tracks[index].kind == .audio {
                drawn.tracks[index].isMuted = true
            }
        }
        return (.composite(drawn, fileType: fileType), sized)
    }

    /// Writes the first of `plans` that fits in `maxBytes`, or the first with none. Each is estimated only once the ones
    /// before it are ruled out, since a GIF's estimate reads frames. One written that's still too big moves on to the
    /// next whose estimate, corrected by how far off this one's was, fits.
    static func fit<Step>(
        _ plans: [(Step, VideoExportPlan)], maxBytes: Int?, to output: URL, canvasType: any Canvas.Type, reader: any VideoReader, assembler: any VideoAssembler,
        describe: (Step) -> String
    ) async throws(ShotCommandError) -> (step: Step, plan: VideoExportPlan, outcome: VideoExportPlan.Outcome) {
        guard let maxBytes else {
            return (plans[0].0, plans[0].1, try await write(plans[0].1, to: output, canvasType: canvasType, assembler: assembler))
        }
        var ratio = 1.0
        for (step, plan) in plans {
            let estimate: Int
            do {
                estimate = try await plan.estimate(canvasType: canvasType, reader: reader)
            } catch {
                throw .io("couldn't estimate the size: \(error.localizedDescription)")
            }
            guard SizeFit.fits(estimate: estimate, ratio: ratio, within: maxBytes) else {
                continue
            }
            let outcome = try await write(plan, to: output, canvasType: canvasType, assembler: assembler)
            let written = bytes(of: output)
            if written <= maxBytes {
                return (step, plan, outcome)
            }
            try? FileManager.default.removeItem(at: output)
            ratio = max(ratio, Double(written) / Double(max(estimate, 1)))
        }
        throw .data("maxBytes: even at \(describe(plans[plans.count - 1].0)) it's over \(maxBytes) bytes; cut more of it, or speed it up")
    }

    static func write(_ plan: VideoExportPlan, to output: URL, canvasType: any Canvas.Type, assembler: any VideoAssembler) async throws(ShotCommandError) -> VideoExportPlan.Outcome {
        do {
            return try await plan.run(to: output, canvasType: canvasType, assembler: assembler)
        } catch {
            throw .io("couldn't write the video: \(error.localizedDescription)")
        }
    }

    // MARK: Output

    /// Where a command writes: `output` when given, which must not exist yet and must end in one of `extensions`, or
    /// else beside `input` with the `default` extension, as its next version when that name is taken. `exact` says a
    /// name taken meanwhile is an error rather than a reason to pick the next one.
    static func destination(for input: URL, output: String?, extensions: [String], default ext: String, command: String) throws(ShotCommandError) -> (url: URL, exact: Bool) {
        if let output {
            let url = url(output)
            guard extensions.contains(url.pathExtension.lowercased()) else {
                throw .usage(command == "draw" ? nil : command, "-o \(output) must end in .\(extensions.joined(separator: ", ."))")
            }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isFolder), isFolder.boolValue else {
                throw .cantCreate("the folder \(url.deletingLastPathComponent().path) doesn't exist")
            }
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw .cantCreate("\(url.path) already exists, and shot never overwrites")
            }
            return (url, true)
        }
        return (VersionNaming.commandOutputURL(for: input, pathExtension: ext), false)
    }

    /// A hidden file in the same folder as `url`, so moving it there is a rename on one volume.
    static func temporaryURL(beside url: URL, pathExtension: String) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".shot-\(UUID().uuidString).\(pathExtension)")
    }

    /// Moves `temporary` to `target` without ever replacing a file: `renamex_np` with `RENAME_EXCL` fails if the name is
    /// taken, which no check made beforehand can promise. A taken name moves on to the next version, unless it was asked for.
    static func place(_ temporary: URL, at target: (url: URL, exact: Bool)) throws(ShotCommandError) -> URL {
        var url = target.url
        for _ in 0 ..< 1000 {
            if renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL)) == 0 {
                return url
            }
            let failure = errno
            guard failure == EEXIST else {
                throw .cantCreate("couldn't write \(url.path): \(String(cString: strerror(failure)))")
            }
            guard !target.exact else {
                throw .cantCreate("\(url.path) already exists, and shot never overwrites")
            }
            url = VersionNaming.nextVersionURL(of: url)
        }
        throw .cantCreate("couldn't find a free name beside \(target.url.path)")
    }

    /// `path`, `size` and `bytes` for a file just written.
    static func written(_ url: URL, codec: any ImageCoding) throws(ShotCommandError) -> [String: JSONValue] {
        var object: [String: JSONValue] = ["path": .string(url.path), "bytes": .number(Double(bytes(of: url)))]
        if let size = codec.info(ofFileAt: url)?.size {
            object["size"] = json(size)
        }
        return object
    }

    // MARK: Helpers

    /// `path` from the command line, relative to the working directory, with `~` expanded.
    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardized
    }

    static func requireInput(_ url: URL) throws(ShotCommandError) {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            throw .noInput("\(url.path) doesn't exist")
        }
        guard !isFolder.boolValue else {
            throw .data("\(url.path) is a folder, not a file")
        }
    }

    static func video(_ url: URL, reader: any VideoReader) async throws(ShotCommandError) -> ImportedMedia {
        try requireInput(url)
        guard let media = try? await MediaProbe.probe(url, reader: reader), media.size != nil else {
            throw .data("\(url.lastPathComponent) isn't a video Shot can read")
        }
        return media
    }

    /// The video `media` as the video editor opens it, with its trim handles dragged to `start` and `end`.
    static func trimmed(_ media: ImportedMedia, start: Double?, end: Double?, command: String) throws(ShotCommandError) -> Project {
        let start = start ?? 0
        guard start < media.duration else {
            throw .usage(command, "the start, \(String(format: "%g", start)) s, is past the end of the \(String(format: "%.2f", media.duration)) s video")
        }
        let whole = Project(source: media.source, duration: media.duration, canvasSize: media.size ?? .zero, hasAudio: media.hasAudio)
        guard let trimmed = whole.trimmingMain(.end, toSource: min(end ?? media.duration, media.duration))?.trimmingMain(.start, toSource: start) else {
            throw .usage(command, "that leaves less than \(String(format: "%g", TrimRange.minimumLength)) s of the video")
        }
        return trimmed
    }

    /// Read afresh each time: `URL.resourceValues` keeps what it read, so a file written again at the same URL would
    /// still give its old size.
    static func bytes(of url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    static func json(_ size: CaptureRecord.Size) -> JSONValue {
        .object(["width": .number(Double(size.width)), "height": .number(Double(size.height))])
    }
}
#endif
