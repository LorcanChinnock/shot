import CoreGraphics
import Foundation

// ShotCore's calls that read or write images take an `ImageCoding`, and those that draw a `Canvas` type. On a Mac they're
// always ImageIO and Core Graphics, so these give the app, ShotCLI and the tests each call as it was, without them.
// CGCanvas+Defaults.swift has the calls that only draw.

extension ProjectEntry {
    public static func encoder() -> JSONEncoder {
        encoder(codec: ImageIOCodec())
    }

    public static func decoder() -> JSONDecoder {
        decoder(codec: ImageIOCodec())
    }
}

extension AnnotationClipboard {
    public static func data(for annotation: Annotation) throws -> Data {
        try data(for: annotation, codec: ImageIOCodec())
    }

    public static func annotation(from data: Data) throws -> Annotation {
        try annotation(from: data, codec: ImageIOCodec())
    }
}

extension ProjectStore {
    public init(folder: URL) {
        self.init(folder: folder, codec: ImageIOCodec())
    }

    public init(bundleID: String) {
        self.init(bundleID: bundleID, codec: ImageIOCodec())
    }
}

extension ProjectStamp {
    public static func id(ofFileAt url: URL) -> String? {
        id(ofFileAt: url, codec: ImageIOCodec())
    }
}

extension TextIndexStore {
    public init(url: URL) {
        self.init(url: url, codec: ImageIOCodec())
    }

    public init(bundleID: String) {
        self.init(bundleID: bundleID, codec: ImageIOCodec())
    }
}

extension TextRecognizer {
    public static func recognize(fileAt url: URL) async throws -> CaptureText? {
        try await recognize(fileAt: url, codec: ImageIOCodec())
    }
}

extension VersionWriter {
    public static func record(of document: EditorDocument, drawnOn original: URL, savedAs format: ImageFormat, scale: CGFloat, atOneX: Bool = false) -> CaptureRecord {
        record(of: document, drawnOn: original, savedAs: format, scale: scale, atOneX: atOneX, codec: ImageIOCodec(), shaper: CoreTextShaper())
    }

    public static func render(_ document: EditorDocument, scale: CGFloat, as format: ImageFormat, record: CaptureRecord?, projectID: String? = nil, atOneX: Bool = false) throws(Failure) -> RenderedImage {
        try render(document, scale: scale, as: format, record: record, projectID: projectID, atOneX: atOneX, codec: ImageIOCodec(), canvasType: CGCanvas.self)
    }

    public static func saveImage(
        _ document: EditorDocument, of original: URL, scale: CGFloat, recordForAgents: Bool = Preferences().agentHandoff,
        projects: ProjectStore? = nil, origin: ProjectOrigin = ProjectOrigin(via: .app)
    ) throws(Failure) -> SavedImage {
        try saveImage(document, of: original, scale: scale, recordForAgents: recordForAgents, projects: projects, origin: origin, codec: ImageIOCodec(), canvasType: CGCanvas.self)
    }

    public static func savedLayers(of url: URL, in projects: ProjectStore?) -> (original: URL, image: CGImage, layers: EditorSnapshot)? {
        savedLayers(of: url, in: projects, codec: ImageIOCodec())
    }
}

extension ShotCommands {
    public static func run(_ command: ShotCommand, projects: ProjectStore? = nil, origin: ProjectOrigin? = nil) async throws(ShotCommandError) -> JSONValue {
        try await run(command, projects: projects, origin: origin, codec: ImageIOCodec(), canvasType: CGCanvas.self, reader: AVVideoReader(), assembler: AVVideoAssembler())
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
            folder: folder, marks: marks, projects: projects, texts: texts, codec: ImageIOCodec(), canvasType: CGCanvas.self, reader: AVVideoReader(),
            assembler: AVVideoAssembler(), agent: agent
        )
    }
}
