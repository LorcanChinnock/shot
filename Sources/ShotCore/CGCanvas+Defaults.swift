import AVFoundation
import CoreGraphics
import Foundation

// ShotCore's calls that draw take a `Canvas`, or the `Canvas` type to make one with. On a Mac it's always Core Graphics,
// so these give the app, ShotCLI and the tests each call as it was, with a `CGContext` or without a canvas.

extension AnnotationRenderer {
    /// Draws the document into a bottom-left-origin context of size `doc.exportSize`.
    public static func render(_ doc: EditorDocument, into ctx: CGContext) {
        render(doc, into: CGCanvas(ctx))
    }

    public static func flatten(_ doc: EditorDocument) -> CGImage? {
        flatten(doc, canvasType: CGCanvas.self)
    }

    /// Draws in a top-left-origin context. `below` are the annotations drawn before it, which a pixelate or blur
    /// covers along with the screenshot. `background` is the canvas's, which tints a shadow.
    public static func draw(_ annotation: Annotation, base: CGImage, over below: ArraySlice<Annotation> = [], background: RGBA? = nil, in ctx: CGContext) {
        draw(annotation, base: base, over: below, background: background, in: CGCanvas(ctx))
    }
}

extension ImageCodec {
    /// Resamples a Retina capture to 1 pixel per point.
    public static func downscaled(_ image: CGImage, scale: CGFloat) -> CGImage {
        downscaled(image, scale: scale, canvasType: CGCanvas.self)
    }
}

extension ImageTrim {
    /// Crops away fully transparent rows and columns at the edges.
    public static func trimTransparentEdges(_ image: CGImage) -> CGImage {
        trimTransparentEdges(image, canvasType: CGCanvas.self)
    }
}

extension ShotCommands {
    /// `image` drawn at `width` by `height`, read as 8-bit premultiplied sRGB RGBA, top row first.
    package static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        pixels(of: image, width: width, height: height, canvasType: CGCanvas.self)
    }
}

extension StyleThumbnail {
    public static func render(
        _ subject: Subject, style: ObjectStyle, cornerRadius: CGFloat, size: CGSize, pixelsPerPoint: CGFloat, background: RGBA? = nil
    ) -> CGImage? {
        render(subject, style: style, cornerRadius: cornerRadius, size: size, pixelsPerPoint: pixelsPerPoint, background: background, canvasType: CGCanvas.self)
    }
}

extension CopiedStyle {
    public func styledCapture(_ image: CGImage, scale: CGFloat, background: RGBA?, windowShadow: Bool = false) -> CGImage? {
        styledCapture(image, scale: scale, background: background, windowShadow: windowShadow, canvasType: CGCanvas.self)
    }
}

extension CompositionBuilder {
    public static func build(_ project: Project) async throws -> ProjectComposition {
        try await build(project, canvasType: CGCanvas.self)
    }
}

extension ProjectExporter {
    public static func export(_ project: Project, to output: URL, as fileType: AVFileType = .mp4) async throws {
        try await export(project, to: output, as: fileType, canvasType: CGCanvas.self)
    }
}

extension VideoExportPlan {
    @discardableResult
    public func run(to output: URL, progress: @Sendable (Double) -> Void = { _ in }) async throws -> Outcome {
        try await run(to: output, canvasType: CGCanvas.self, progress: progress)
    }

    public func estimate() async throws -> Int {
        try await estimate(canvasType: CGCanvas.self)
    }
}

extension VersionWriter {
    @discardableResult
    public static func writeVideo(
        _ plan: VideoExportPlan, of project: Project, original: URL, to output: URL, projects: ProjectStore? = nil,
        origin: ProjectOrigin = ProjectOrigin(via: .app), progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> VideoExportPlan.Outcome {
        try await writeVideo(
            plan, of: project, original: original, to: output, projects: projects, origin: origin, canvasType: CGCanvas.self, progress: progress
        )
    }
}

extension KeyFrameExtractor {
    public static func changeTimes(in url: URL, duration: Double, count: Int) async throws -> [Double] {
        try await changeTimes(in: url, duration: duration, count: count, canvasType: CGCanvas.self)
    }

    /// `image` drawn into a small grayscale bitmap, as bytes.
    public static func gray(_ image: CGImage) -> [UInt8] {
        gray(image, canvasType: CGCanvas.self)
    }
}

extension GIFStreamWriter {
    package convenience init(output: @escaping (Data) throws -> Void) {
        self.init(canvasType: CGCanvas.self, output: output)
    }
}

extension GIFExporter {
    @discardableResult
    public static func export(
        videoURL: URL,
        to outputURL: URL,
        range: TrimRange? = nil,
        cuts: CutList = CutList(),
        fps: Double = 12,
        maxWidth: CGFloat? = 720,
        speed: Double = 1,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        try await export(
            videoURL: videoURL, to: outputURL, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed, canvasType: CGCanvas.self,
            progress: progress
        )
    }

    /// Writes the whole of `composition` as a looping GIF, as `export(videoURL:…)` does for a file.
    @discardableResult
    public static func export(
        composition: ProjectComposition,
        to outputURL: URL,
        fps: Double = 12,
        maxWidth: CGFloat? = 720,
        speed: Double = 1,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        try await export(VideoFrames(composition), to: outputURL, fps: fps, maxWidth: maxWidth, speed: speed, canvasType: CGCanvas.self, progress: progress)
    }

    public static func estimatedSize(
        of videoURL: URL, range: TrimRange? = nil, cuts: CutList = CutList(), fps: Double, maxWidth: CGFloat?, speed: Double = 1
    ) async throws -> Int {
        try await estimatedSize(of: videoURL, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed, canvasType: CGCanvas.self)
    }

    public static func estimatedSize(of composition: ProjectComposition, fps: Double, maxWidth: CGFloat?, speed: Double = 1) async throws -> Int {
        try await estimatedSize(of: VideoFrames(composition), fps: fps, maxWidth: maxWidth, speed: speed, canvasType: CGCanvas.self)
    }
}

extension VersionWriter {
    public static func render(_ document: EditorDocument, scale: CGFloat, as format: ImageFormat, record: CaptureRecord?, projectID: String? = nil, atOneX: Bool = false) throws(Failure) -> RenderedImage {
        try render(document, scale: scale, as: format, record: record, projectID: projectID, atOneX: atOneX, canvasType: CGCanvas.self)
    }

    public static func saveImage(
        _ document: EditorDocument, of original: URL, scale: CGFloat, recordForAgents: Bool = Preferences().agentHandoff,
        projects: ProjectStore? = nil, origin: ProjectOrigin = ProjectOrigin(via: .app)
    ) throws(Failure) -> SavedImage {
        try saveImage(document, of: original, scale: scale, recordForAgents: recordForAgents, projects: projects, origin: origin, canvasType: CGCanvas.self)
    }
}

extension ShotCommands {
    public static func run(_ command: ShotCommand, projects: ProjectStore? = nil, origin: ProjectOrigin? = nil) async throws(ShotCommandError) -> JSONValue {
        try await run(command, projects: projects, origin: origin, canvasType: CGCanvas.self)
    }
}

extension AgentTools {
    public static func live(
        folder: URL,
        marks: URL? = nil,
        projects: ProjectStore? = nil,
        texts: TextIndexStore? = nil,
        agent: @escaping @Sendable (AgentRequest) async throws(ShotCommandError) -> [String: JSONValue] = { _ throws(ShotCommandError) in throw .unavailable("can't reach Shot from here") }
    ) -> AgentTools {
        live(
            folder: folder, marks: marks, projects: projects, textIndex: { texts?.load() ?? TextIndex() }, canvasType: CGCanvas.self, agent: agent
        )
    }
}
