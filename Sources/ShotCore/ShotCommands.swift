import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Runs the `shot` media commands with no window, display or permission, for the command line and the MCP tools. Each
/// writes a new file and never touches its input: the result goes beside the input as its next version unless an output
/// that doesn't exist yet is named, and it's moved into place in one step that fails rather than replace anything.
public enum ShotCommands {
    /// The JSON a command prints: at least `path`, `size` and `bytes` for what it wrote, or what `info` found.
    public static func run(_ command: ShotCommand) async throws(ShotCommandError) -> JSONValue {
        switch command {
        case let .info(path):
            return try await info(url(path))
        case let .gif(options):
            return try await gif(options)
        case let .trim(options):
            return try await trim(options)
        case let .redact(options):
            return try draw(input: options.input, output: options.output) { (image: CGImage) throws(ShotCommandError) in
                let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                var annotations: [Annotation] = []
                for (index, r) in options.rects.enumerated() {
                    let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3]).intersection(bounds)
                    guard !rect.isNull, rect.width >= 1, rect.height >= 1 else {
                        throw .data("rect \(index + 1) (\(r.map { String(format: "%g", $0) }.joined(separator: ","))) is off the \(image.width)×\(image.height) image")
                    }
                    let kind: Annotation.Kind = options.style == .blur ? .blur(rect) : .pixelate(rect)
                    annotations.append(Annotation(kind: kind, color: RGBA.presets[0], lineWidth: EditorStyle.widths[1]))
                }
                return annotations
            }
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
            return try draw(input: options.input, output: options.output) { (_: CGImage, scale: CGFloat) throws(ShotCommandError) in
                var annotations: [Annotation] = []
                for (index, mark) in marks.enumerated() {
                    // Widths an agent leaves out look as they would drawn in the editor at the capture's scale.
                    guard let annotation = Annotation(mark: mark, lineWidth: EditorStyle.widths[1] * scale) else {
                        throw .data("mark \(index) (\(mark.type)) can't be drawn")
                    }
                    annotations.append(annotation)
                }
                return annotations
            }
        case let .frames(options):
            return try await frames(options)
        case let .text(path):
            return try await text(url(path))
        case let .diff(options):
            return try diff(options)
        case .capture, .record, .watch, .windows, .mcp, .version, .help:
            throw .internal("\(command.name) isn't a media command")
        }
    }

    // MARK: Commands

    static func info(_ url: URL) async throws(ShotCommandError) -> JSONValue {
        try requireInput(url)
        var object: [String: JSONValue] = ["path": .string(url.path), "bytes": .number(Double(bytes(of: url)))]
        if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
            object["created"] = .string(ISO8601DateFormatter().string(from: created))
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
           let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) }), type.conforms(to: .image),
           let size = pixelSize(source) {
            object["kind"] = .string(type.conforms(to: .gif) ? "gif" : "image")
            object["size"] = size
            object["scale"] = .number(Double(ImageCodec.scale(ofFileAt: url)))
            if CGImageSourceGetCount(source) > 1 {
                object["frames"] = .number(Double(CGImageSourceGetCount(source)))
            }
            if let record = ImageCodec.record(ofFileAt: url), let data = try? record.encoded(),
               let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                object["record"] = value
            }
            return .object(object)
        }
        guard let media = try? await MediaProbe.probe(url) else {
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

    static func gif(_ options: ShotCommand.GIFOptions) async throws(ShotCommandError) -> JSONValue {
        let input = url(options.input)
        let duration = try await videoDuration(input)
        let range = try range(start: options.start, end: options.end, duration: duration, command: "gif")
        let target = try destination(for: input, output: options.output, extensions: ["gif"], default: "gif", command: "gif")
        let temporary = temporaryURL(beside: target.url, pathExtension: "gif")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result: GIFExporter.Result
        do {
            result = try await GIFExporter.export(
                videoURL: input, to: temporary, range: range, fps: options.fps, maxWidth: options.width == 0 ? nil : CGFloat(options.width)
            )
        } catch {
            throw .io("couldn't make the GIF: \(error.localizedDescription)")
        }
        let placed = try place(temporary, at: target)
        var object = try written(placed)
        object["frames"] = .number(Double(result.frameCount))
        object["truncated"] = .bool(result.truncated)
        return .object(object)
    }

    static func trim(_ options: ShotCommand.TrimOptions) async throws(ShotCommandError) -> JSONValue {
        let input = url(options.input)
        let duration = try await videoDuration(input)
        let range = try range(start: options.start, end: options.end, duration: duration, command: "trim")
        let own = input.pathExtension.lowercased()
        let target = try destination(for: input, output: options.output, extensions: ["mov", "mp4"], default: ["mov", "mp4"].contains(own) ? own : "mov", command: "trim")
        let fileType: AVFileType = target.url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        let temporary = temporaryURL(beside: target.url, pathExtension: target.url.pathExtension)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try await VideoTrimmer.trim(input, range: range, to: temporary, as: fileType)
        } catch {
            throw .io("couldn't trim the video: \(error.localizedDescription)")
        }
        let placed = try place(temporary, at: target)
        var object = try written(placed)
        if let media = try? await MediaProbe.probe(placed) {
            object["duration"] = .number((media.duration * 1000).rounded() / 1000)
            if let size = media.size {
                object["size"] = .object(["width": .number(Double(Int(size.width))), "height": .number(Double(Int(size.height)))])
            }
        }
        return .object(object)
    }

    static func frames(_ options: ShotCommand.FramesOptions) async throws(ShotCommandError) -> JSONValue {
        let input = url(options.input)
        let duration = try await videoDuration(input)
        let times: [Double]
        if let every = options.every {
            times = Array(stride(from: 0, to: duration, by: every))
            guard times.count <= ShotCommand.FramesOptions.maximumEvery else {
                throw .usage("frames", "--every \(String(format: "%g", every)) gives \(times.count) frames of the \(String(format: "%.1f", duration)) s video; the most is \(ShotCommand.FramesOptions.maximumEvery)")
            }
        } else {
            do {
                times = try await KeyFrameExtractor.changeTimes(in: input, duration: duration, count: options.count)
            } catch {
                throw .io("couldn't read the video's frames: \(error.localizedDescription)")
            }
        }
        let folder = try makeFolder(beside: input, output: options.output)
        do {
            let frames = try await KeyFrameExtractor.frames(of: input, at: times, maxWidth: options.width)
            var written: [JSONValue] = []
            for (index, frame) in frames.enumerated() {
                let file = folder.appendingPathComponent(String(format: "%02d %.1fs.jpg", index + 1, frame.time))
                guard let data = ImageCodec.data(from: frame.image, scale: 1, format: .jpeg) else {
                    throw ShotCommandError.internal("couldn't encode the frame at \(String(format: "%.1f", frame.time)) s")
                }
                try data.write(to: file, options: .withoutOverwriting)
                var object = try Self.written(file)
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

    static func text(_ url: URL) async throws(ShotCommandError) -> JSONValue {
        try requireInput(url)
        guard let image = ImageCodec.image(at: url) else {
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

    /// Draws the annotations `make` gives for the input image, and the image's scale, onto a copy of it, recording them
    /// inside the new file so a person can open it in Shot and change them. The record and the drawing are the editor's,
    /// from `VersionWriter`; unlike the editor, a command records whether or not agents are handed captures.
    static func draw(input path: String, output: String?, _ make: (CGImage, CGFloat) throws(ShotCommandError) -> [Annotation]) throws(ShotCommandError) -> JSONValue {
        let input = url(path)
        try requireInput(input)
        guard let image = ImageCodec.image(at: input) else {
            throw .data("\(input.lastPathComponent) isn't an image Shot can read")
        }
        let own = input.pathExtension.lowercased()
        let target = try destination(for: input, output: output, extensions: ["png", "jpg", "jpeg"], default: ["png", "jpg", "jpeg"].contains(own) ? own : "png", command: "draw")
        let format = ImageFormat(fileExtension: target.url.pathExtension)
        let scale = ImageCodec.scale(ofFileAt: input)
        var document = EditorDocument(base: image, annotations: try make(image, scale), background: EditorDocument.defaultBackground(for: format))
        document.hasWindowShadow = ImageCodec.hasWindowShadow(ofFileAt: input)
        defer { AnnotationRenderer.releaseCaches() }
        let data: Data
        do throws(VersionWriter.Failure) {
            let record = VersionWriter.record(of: document, drawnOn: input, savedAs: format, scale: scale)
            data = try VersionWriter.render(document, scale: scale, as: format, record: record).file
        } catch .draw {
            throw .internal("couldn't draw the image")
        } catch {
            throw .internal("couldn't encode the image")
        }
        let temporary = temporaryURL(beside: target.url, pathExtension: target.url.pathExtension)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            throw .cantCreate("couldn't write in \(temporary.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        return .object(try written(place(temporary, at: target)))
    }

    /// The same for `redact`, which needs only the image.
    static func draw(input path: String, output: String?, _ make: (CGImage) throws(ShotCommandError) -> [Annotation]) throws(ShotCommandError) -> JSONValue {
        try draw(input: path, output: output) { (image: CGImage, _: CGFloat) throws(ShotCommandError) in try make(image) }
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
    static func written(_ url: URL) throws(ShotCommandError) -> [String: JSONValue] {
        var object: [String: JSONValue] = ["path": .string(url.path), "bytes": .number(Double(bytes(of: url)))]
        if let size = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(pixelSize) {
            object["size"] = size
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

    static func videoDuration(_ url: URL) async throws(ShotCommandError) -> Double {
        try requireInput(url)
        guard let media = try? await MediaProbe.probe(url), media.size != nil else {
            throw .data("\(url.lastPathComponent) isn't a video Shot can read")
        }
        return media.duration
    }

    static func range(start: Double?, end: Double?, duration: Double, command: String) throws(ShotCommandError) -> TrimRange {
        let start = start ?? 0
        guard start < duration else {
            throw .usage(command, "the start, \(String(format: "%g", start)) s, is past the end of the \(String(format: "%.2f", duration)) s video")
        }
        return TrimRange(start: start, end: min(end ?? duration, duration), duration: duration)
    }

    static func bytes(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func pixelSize(_ source: CGImageSource) -> JSONValue? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return .object(["width": .number(Double(width)), "height": .number(Double(height))])
    }
}
