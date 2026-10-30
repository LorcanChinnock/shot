import CoreGraphics
import Foundation
import os

private let log = Logger.shot("projects")

/// Writes an edit as a new file, so the image editor and the video editor name, draw and keep
/// a version the same way. The naming itself is `VersionNaming`.
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

    /// A drawn version: the image and the file's bytes.
    public struct RenderedImage: @unchecked Sendable {
        public let image: CGImage
        public let file: Data
    }

    /// A version written to disk, and its PNG for the clipboard.
    public struct SavedImage: Sendable {
        public let url: URL
        public let png: Data
        /// The file whose pixels the layers sit on: the one saved from, or the copy kept when saving over it.
        public let original: URL
    }

    /// The next version of `url` for a file written as `format`. It keeps the original's extension when that names
    /// `format`, so "a.jpeg" gives "a (2).jpeg", and otherwise takes the format's own, so "a.heic" saved as PNG gives "a (2).png".
    public static func nextVersionURL(of url: URL, savedAs format: ImageFormat, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let ext = keepsExtension(of: url, savedAs: format) ? url.pathExtension : format.fileExtension
        return VersionNaming.nextVersionURL(of: url.deletingPathExtension().appendingPathExtension(ext), exists: exists)
    }

    /// Whether `url`'s extension already names `format`, so a file saved as `format` can take its place.
    static func keepsExtension(of url: URL, savedAs format: ImageFormat) -> Bool {
        (format == .png ? ["png"] : ["jpg", "jpeg"]).contains(url.pathExtension.lowercased())
    }

    /// Flattens `document` and encodes it as `format`, with `projectID` stamped in it when it has a project. `atOneX` scales it to one pixel per point, as
    /// Settings › Scale Retina captures to 1× does a capture.
    public static func render(_ document: EditorDocument, scale: CGFloat, as format: ImageFormat, projectID: String? = nil, atOneX: Bool = false) throws(Failure) -> RenderedImage {
        guard var image = AnnotationRenderer.flatten(document) else {
            throw .draw
        }
        if atOneX {
            image = ImageCodec.downscaled(image, scale: scale)
        }
        // A window with the macOS shadow still has it once saved, so the file keeps saying so.
        guard let file = ImageCodec.data(from: image, scale: atOneX ? 1 : scale, format: format, windowShadow: document.hasWindowShadow, projectID: projectID) else {
            throw .encode
        }
        return RenderedImage(image: image, file: file)
    }

    /// Saves `document`, drawn on the file at `original`, as that file's next version in its own format, as the image
    /// editor's Save does. With `overwriting`, it replaces `original` instead, after keeping a copy of it in `projects`
    /// for the layers to sit on, unless `pristine` already is one. A file that isn't saved in its own format, or
    /// no `projects` to keep the copy in, still gets a new version. The version keeps its layers
    /// in `projects`, so it reopens live. A project that can't be written leaves the version
    /// saved, flat, as a version saved before projects is.
    public static func saveImage(
        _ document: EditorDocument, of original: URL, pristine: URL? = nil, overwriting: Bool = false, scale: CGFloat, projects: ProjectStore? = nil
    ) throws(Failure) -> SavedImage {
        let format = ImageFormat(fileExtension: original.pathExtension)
        let overwrites = overwriting && projects != nil && keepsExtension(of: original, savedAs: format)
        var base = pristine ?? original
        if overwrites, pristine == nil, let projects {
            do {
                base = try projects.keepOriginal(copying: original)
            } catch {
                throw .write(error)
            }
        }
        let projectID = projects == nil ? nil : ProjectKey.newID()
        let rendered = try render(document, scale: scale, as: format, projectID: projectID)
        let png: Data
        if format == .png {
            png = rendered.file
        } else {
            guard let data = ImageCodec.data(from: rendered.image, scale: scale, format: .png, windowShadow: document.hasWindowShadow) else {
                throw .encode
            }
            png = data
        }
        let destination = overwrites ? original : nextVersionURL(of: original, savedAs: format)
        do {
            try rendered.file.write(to: destination, options: .atomic)
        } catch {
            throw .write(error)
        }
        keep(document.snapshot, of: destination, id: projectID, original: base, in: projects)
        return SavedImage(url: destination, png: png, original: base)
    }

    /// Puts the pristine copy `pristine` back over `file`, which was saved over, as it was before.
    public static func revert(_ file: URL, to pristine: URL) throws {
        let copy = file.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(file.pathExtension)")
        try FileManager.default.copyItem(at: pristine, to: copy)
        do {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: copy)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }

    /// Keeps `layers`, of the version just written at `url` over `original`, in `projects` under `id`, the ID stamped
    /// in it. A project that can't be written is only logged, so the version stays saved, flat.
    static func keep(_ layers: EditorSnapshot, of url: URL, id: String?, original: URL, in projects: ProjectStore?) {
        guard let projects else {
            return
        }
        do {
            try projects.save(layers, for: url, id: id, original: original)
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
        // A file saved over is no longer what the layers were saved with once something else changes it.
        if projects.keeps(original), !(ProjectFile(at: url, bookmark: false).map(project.entry.file.matches) ?? false) {
            return nil
        }
        return (original, layers)
    }

    /// The original of the image at `url`, its pixels and the live layers that give `url` back: from `projects`, or
    /// `nil` when `url` has none or its original is gone, so it opens flat.
    public static func savedLayers(of url: URL, in projects: ProjectStore?) -> (original: URL, image: CGImage, layers: EditorSnapshot)? {
        if let projects, let project = layers(of: url, in: projects), let image = ImageCodec.image(at: project.original) {
            return (project.original, image, project.layers)
        }
        return nil
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

    /// Writes `plan`, an edit of `project` over the video at `original`, to `output`, as the video editor's Save Copy and
    /// Export do. `project` is kept in `projects`, stamped in an MP4 or MOV and keyed by its identity for a GIF, so the file
    /// reopens with it live. A project that can't be kept leaves the file written, as
    /// one written before projects is.
    @discardableResult
    public static func writeVideo(
        _ plan: VideoExportPlan, of project: Project, original: URL, to output: URL, projects: ProjectStore? = nil,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> VideoExportPlan.Outcome {
        let outcome = try await plan.run(to: output, progress: progress)
        keep(project, of: output, original: original, in: projects)
        return outcome
    }

    /// Keeps `project`, the edit written at `url` over the video at `original`, in `projects`: stamped in an MP4 or
    /// MOV, and keyed by its identity for a GIF. A project that can't be kept is only logged, so the file stays written.
    static func keep(_ project: Project, of url: URL, original: URL, in projects: ProjectStore?) {
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
            try projects.save(project, for: url, id: id, original: original)
        } catch {
            log.error("Couldn't keep the project of \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
