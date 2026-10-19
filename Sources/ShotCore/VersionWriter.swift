#if canImport(AVFoundation) && canImport(CoreGraphics)
import AVFoundation
import CoreGraphics
import Foundation

private let log = ShotLog.shot("projects")

/// Writes an edit as a new file, so the image editor, the video editor and the `shot` commands name, draw and record
/// a version the same way. The naming itself is `VersionNaming`, in ShotModel.
public enum VersionWriter {
    /// Why an image version couldn't be written.
    public enum Failure: Error {
        /// The document couldn't be drawn.
        case draw
        /// The drawn image couldn't be encoded.
        case encode
        /// The file couldn't be written.
        case write(any Error)
    }

    // MARK: Images

    /// A drawn version: the image, the file's bytes, and the record inside them.
    public struct RenderedImage: @unchecked Sendable {
        public let image: CGImage
        public let file: Data
        public let record: CaptureRecord?
    }

    /// A version written to disk, and its PNG for the clipboard.
    public struct SavedImage: Sendable {
        public let url: URL
        public let png: Data
    }

    /// The next version of `url` for a file written as `format`. It keeps the original's extension when that names
    /// `format`, so "a.jpeg" gives "a (2).jpeg", and otherwise takes the format's own, so "a.heic" saved as PNG gives "a (2).png".
    public static func nextVersionURL(of url: URL, savedAs format: ImageFormat, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let names = format == .png ? ["png"] : ["jpg", "jpeg"]
        let ext = names.contains(url.pathExtension.lowercased()) ? url.pathExtension : format.fileExtension
        return VersionNaming.nextVersionURL(of: url.deletingPathExtension().appendingPathExtension(ext), exists: exists)
    }

    /// What a version records for agents: the marks, in the saved file's pixels, the file they're drawn on, which may
    /// itself be a version, and that file's source, so the version still says which app and window it showed. It's
    /// editable when reopening `original` with the marks gives `document` back. The size is filled in once rendered.
    /// `atOneX` is for a file scaled to one pixel per point, whose marks are scaled with it and which can't reopen live.
    public static func record(of document: EditorDocument, drawnOn original: URL, savedAs format: ImageFormat, scale: CGFloat, atOneX: Bool = false, codec: any ImageCoding, shaper: any TextShaper) -> CaptureRecord {
        let canvas = document.canvasRect
        // The file is the canvas at 1:1, or scaled to 1×, so the marks need no other change than the canvas offset.
        return CaptureRecord(
            original: original.lastPathComponent, kind: "image", created: Date(), size: CaptureRecord.Size(width: 0, height: 0), scale: atOneX ? 1 : scale,
            source: codec.record(ofFileAt: original)?.source,
            canvas: [canvas.minX, canvas.minY, canvas.width, canvas.height].map { (Double($0) * 10).rounded() / 10 },
            crop: document.visibleCrop.map { [$0.minX, $0.minY, $0.width, $0.height].map { (Double($0) * 10).rounded() / 10 } },
            editable: !atOneX && CaptureMark.rebuildExactly(document.annotations, canvas: canvas, shaper: shaper) && document.captureStyle.isEmpty && document.captureCornerRadius == 0
                && document.background == EditorDocument.defaultBackground(for: format),
            annotations: CaptureMark.mapping(document.annotations, canvas: canvas, scale: atOneX ? 1 / scale : 1, shaper: shaper)
        )
    }

    /// Flattens `document` on a `canvasType` canvas and encodes it as `format`, with `record` inside it once it has the
    /// drawn size, and `projectID` stamped in it when it has a project. `atOneX` scales it to one pixel per point, as
    /// Settings › Scale Retina captures to 1× does a capture.
    public static func render(_ document: EditorDocument, scale: CGFloat, as format: ImageFormat, record: CaptureRecord?, projectID: String? = nil, atOneX: Bool = false, codec: any ImageCoding, canvasType: any Canvas.Type) throws(Failure) -> RenderedImage {
        guard var image = AnnotationRenderer.flatten(document, canvasType: canvasType) else {
            throw .draw
        }
        if atOneX {
            image = ImageCodec.downscaled(image, scale: scale, canvasType: canvasType)
        }
        var record = record
        record?.size = CaptureRecord.Size(width: image.width, height: image.height)
        // A window with the macOS shadow still has it once saved, so the file keeps saying so.
        let metadata = ImageMetadata(windowShadow: document.hasWindowShadow, record: record, projectID: projectID)
        guard let file = codec.data(from: image, scale: atOneX ? 1 : scale, format: format, metadata: metadata) else {
            throw .encode
        }
        return RenderedImage(image: image, file: file, record: record)
    }

    /// Saves `document`, drawn on the file at `original`, as that file's next version in its own format, as the image
    /// editor's Save does. The version records its marks for agents while `recordForAgents` is on, and keeps its layers
    /// in `projects`, whatever that setting, so it reopens live. A project that can't be written leaves the version
    /// saved, flat, as a version saved before projects is.
    public static func saveImage(
        _ document: EditorDocument, of original: URL, scale: CGFloat, recordForAgents: Bool = Preferences().agentHandoff,
        projects: ProjectStore? = nil, origin: ProjectOrigin = ProjectOrigin(via: .app), codec: any ImageCoding, canvasType: any Canvas.Type
    ) throws(Failure) -> SavedImage {
        let format = ImageFormat(fileExtension: original.pathExtension)
        let record = recordForAgents ? record(of: document, drawnOn: original, savedAs: format, scale: scale, codec: codec, shaper: canvasType.shaper) : nil
        let projectID = projects == nil ? nil : ProjectKey.newID()
        let rendered = try render(document, scale: scale, as: format, record: record, projectID: projectID, codec: codec, canvasType: canvasType)
        let png: Data
        if format == .png {
            png = rendered.file
        } else {
            guard let data = codec.data(from: rendered.image, scale: scale, format: .png, metadata: ImageMetadata(windowShadow: document.hasWindowShadow, record: rendered.record)) else {
                throw .encode
            }
            png = data
        }
        let destination = nextVersionURL(of: original, savedAs: format)
        do {
            try rendered.file.write(to: destination, options: .atomic)
        } catch {
            throw .write(error)
        }
        keep(document.snapshot, of: destination, id: projectID, original: original, in: projects, origin: origin)
        return SavedImage(url: destination, png: png)
    }

    /// Keeps `layers`, of the version just written at `url` over `original`, in `projects` under `id`, the ID stamped
    /// in it. A project that can't be written is only logged, so the version stays saved, flat.
    static func keep(_ layers: EditorSnapshot, of url: URL, id: String?, original: URL, in projects: ProjectStore?, origin: ProjectOrigin) {
        guard let projects else {
            return
        }
        do {
            try projects.save(layers, for: url, id: id, original: original, origin: origin)
        } catch {
            log.error("Couldn't keep the layers of \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The original the image at `url` was saved from and its layers, when `url` is a version with a project in
    /// `projects` and that original is still the file it was. Opening the original with them gives the version back, live.
    public static func layers(of url: URL, in projects: ProjectStore) -> (original: URL, layers: EditorSnapshot)? {
        guard let project = projects.project(for: url, as: EditorSnapshot.self), let layers = project.document,
              let kept = project.entry.original, let original = kept.locate(),
              let found = ProjectFile(at: original, bookmark: false), kept.matches(found), original.standardizedFileURL != url.standardizedFileURL
        else {
            return nil
        }
        return (original, layers)
    }

    /// The original of the image at `url`, its pixels and the live layers that give `url` back: from `projects`, or
    /// else from a record that can rebuild them, for a version saved before projects. `nil` when `url` has neither or
    /// its original is gone, so it opens, or is drawn on, flat.
    public static func savedLayers(of url: URL, in projects: ProjectStore?, codec: any ImageCoding) -> (original: URL, image: CGImage, layers: EditorSnapshot)? {
        if let projects, let project = layers(of: url, in: projects), let image = codec.image(at: project.original) {
            return (project.original, image, project.layers)
        }
        guard let record = codec.record(ofFileAt: url), let layers = record.editableLayers, let name = record.original else {
            return nil
        }
        let original = url.deletingLastPathComponent().appendingPathComponent(name)
        guard original != url, let image = codec.image(at: original) else {
            return nil
        }
        var document = EditorDocument(
            base: image, annotations: layers.annotations, canvasRect: layers.canvas,
            background: EditorDocument.defaultBackground(for: ImageFormat(fileExtension: original.pathExtension))
        )
        if let crop = layers.crop {
            document.crop(to: crop)
        }
        return (original, image, document.snapshot)
    }

    // MARK: Videos

    /// A new file beside the video at `original` for a copy of an edit of it, named as a new capture is.
    public static func videoCopyURL(of original: URL, prefix: String, date: Date = Date()) -> URL {
        FileNaming.uniqueURL(in: original.deletingLastPathComponent(), date: date, pathExtension: VersionNaming.videoCopyExtension(of: original), prefix: prefix)
    }

    /// How an edit of the video at `original` is written by Save, Save Copy and Copy: in the recording's format when
    /// AVFoundation can write it, and as MP4 otherwise.
    public static func videoPlan(for project: Project, of original: URL) -> VideoExportPlan {
        VideoExportPlan.copy(of: project, as: VersionNaming.videoCopyExtension(of: original) == "mov" ? .mov : .mp4)
    }

    /// Writes `plan`, an edit of `project` over the video at `original`, to `output`, its annotations drawn on `canvasType`
    /// canvases, as the video editor's Save Copy and Export do. `project` is kept in `projects`, stamped in an MP4 or MOV and keyed by its identity for a GIF, so
    /// the file reopens with it live. A project that can't be kept leaves the file written, as one written before
    /// projects is.
    @discardableResult
    public static func writeVideo(
        _ plan: VideoExportPlan, of project: Project, original: URL, to output: URL, projects: ProjectStore? = nil,
        origin: ProjectOrigin = ProjectOrigin(via: .app), canvasType: any Canvas.Type, progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> VideoExportPlan.Outcome {
        let outcome = try await plan.run(to: output, canvasType: canvasType, progress: progress)
        keep(project, of: output, original: original, in: projects, origin: origin)
        return outcome
    }

    /// Keeps `project`, the edit written at `url` over the video at `original`, in `projects`: stamped in an MP4 or
    /// MOV, and keyed by its identity for a GIF. A project that can't be kept is only logged, so the file stays written.
    static func keep(_ project: Project, of url: URL, original: URL, in projects: ProjectStore?, origin: ProjectOrigin) {
        guard let projects else {
            return
        }
        do {
            var id: String?
            if ProjectKey.stamps(pathExtension: url.pathExtension) {
                let minted = ProjectKey.newID()
                try ProjectStamp.stamp(movieAt: url, id: minted)
                id = minted
            }
            try projects.save(project, for: url, id: id, original: original, origin: origin)
        } catch {
            log.error("Couldn't keep the project of \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Keeps only who made the capture or recording at `url`, such as an agent's, which has no layers. `id` is the ID
    /// already stamped in an image; a movie is stamped here, so write it first. A failure is only logged, since the
    /// capture is saved either way.
    public static func keep(origin: ProjectOrigin, of url: URL, id: String?, in projects: ProjectStore) {
        do {
            var id = id
            if id == nil, ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
                let minted = ProjectKey.newID()
                try ProjectStamp.stamp(movieAt: url, id: minted)
                id = minted
            }
            try projects.save(origin: origin, for: url, id: id)
        } catch {
            log.error("Couldn't keep who made \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stamps the video at `url` again with the ID in `entry`, its entry from before Save trimmed it in place, which
    /// wrote a new file without it. It's the same capture, so it keeps who made it, but it's its own original now, so
    /// any layers kept for it, which were over the untrimmed footage, are dropped.
    public static func restamp(trimmed url: URL, as entry: ProjectEntry, in projects: ProjectStore) {
        guard entry.stamped else {
            return
        }
        do {
            try ProjectStamp.stamp(movieAt: url, id: entry.id)
            try projects.save(origin: entry.origin, for: url, id: entry.id)
        } catch {
            log.error("Couldn't stamp the trimmed \(url.lastPathComponent, privacy: .public) again: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A video edit reopened from its project: the recording it was made over, the project with its clips pointed at
    /// where their files are now, and the imported files it had to leave out because they're gone.
    public struct ReopenedVideo: Sendable {
        public let original: URL
        public let project: Project
        public let missing: [URL]
    }

    /// The project of the video or GIF at `url`, when it has one in `projects` and the recording it was made over is
    /// still the file it was. A recording that moved is followed by its bookmark, and an import that's gone is looked
    /// for where it was relative to the recording, in case they moved together; one still missing is left out, with its
    /// clips. `nil` when that would leave too little on the main track, so the file opens as itself.
    public static func project(of url: URL, in projects: ProjectStore) -> ReopenedVideo? {
        guard let stored = projects.project(for: url, as: Project.self), let project = stored.document,
              let kept = stored.entry.original, let original = kept.locate(),
              let found = ProjectFile(at: original, bookmark: false), kept.matches(found), original.standardizedFileURL != url.standardizedFileURL
        else {
            return nil
        }
        let was = URL(fileURLWithPath: kept.path)
        var located: [URL: URL] = [:]
        var missing: [URL] = []
        for source in Set(project.tracks.flatMap(\.clips).map(\.source)) {
            if let now = locate(source, recordingWas: was, isNow: original) {
                located[source] = now
            } else {
                missing.append(source)
            }
        }
        var relocated = project
        for track in relocated.tracks.indices {
            for clip in relocated.tracks[track].clips.indices {
                let source = relocated.tracks[track].clips[clip].source
                relocated.tracks[track].clips[clip].source = located[source] ?? source
            }
        }
        guard let reopened = relocated.removingClips(from: Set(missing)) else {
            return nil
        }
        return ReopenedVideo(original: original, project: reopened, missing: missing.sorted { $0.path < $1.path })
    }

    /// Where `source`, a clip's file, is now: the recording wherever it went, an import where it was, or else at the
    /// same place relative to the recording, for an import kept beside it whose folder moved.
    private static func locate(_ source: URL, recordingWas was: URL, isNow now: URL) -> URL? {
        let path = source.standardizedFileURL.path
        if path == was.standardizedFileURL.path {
            return now
        }
        if FileManager.default.fileExists(atPath: path) {
            return source
        }
        let folder = was.deletingLastPathComponent().standardizedFileURL.path + "/"
        guard path.hasPrefix(folder) else {
            return nil
        }
        let moved = now.deletingLastPathComponent().appendingPathComponent(String(path.dropFirst(folder.count)))
        return FileManager.default.fileExists(atPath: moved.path) ? moved : nil
    }
}
#endif
