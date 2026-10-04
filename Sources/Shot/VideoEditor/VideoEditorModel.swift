import AppKit
import AVFoundation
import Observation
import os
import ShotCore

private let log = Logger.shot("video-editor")

/// What one undo step restores.
struct VideoEdit: Equatable {
    var range: TrimRange
    var cuts: CutList
    var options: VideoExportOptions
}

@MainActor
@Observable
final class VideoEditorModel {
    let fileURL: URL
    let player = AVPlayer()
    private(set) var duration: Double = 0
    private(set) var aspectRatio: CGFloat = 16 / 9
    private(set) var range = TrimRange(duration: 0)
    /// Sections removed from inside `range`; Copy, Save and Export all leave them out.
    private(set) var cuts = CutList()
    /// The section a Shift-drag on the timeline marked, which Delete cuts.
    private(set) var selection: Range<Double>?
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var isExporting = false
    private(set) var thumbnails: [CGImage?] = []
    /// Applies to Export only; Copy and Save keep the original format, speed and sound.
    private(set) var options = Preferences().videoExportOptions
    /// Bytes Export would write, or nil until it's worked out.
    private(set) var estimatedSize: Int?
    private(set) var undoStack = UndoStack<VideoEdit>()

    @ObservationIgnored private var dragOrigin: TrimRange?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var cutObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init(fileURL: URL) {
        self.fileURL = fileURL
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                self?.isPlaying = playing
            }
        }
    }

    var isDirty: Bool { !range.isFull(duration: duration) || !cuts.isEmpty }

    var edit: VideoEdit { VideoEdit(range: range, cuts: cuts, options: options) }

    /// How long Copy and Save run for: the range less the cuts.
    var keptLength: Double { cuts.keptLength(in: range) }

    /// Loads (or reloads, after a save) the file; false when it has no video to show.
    func load() async -> Bool {
        let asset = AVURLAsset(url: fileURL)
        do {
            let duration = try await asset.load(.duration).seconds
            guard duration > 0, let track = try await asset.loadTracks(withMediaType: .video).first else {
                return false
            }
            let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
            let size = naturalSize.applying(transform)
            self.duration = duration
            aspectRatio = size.height == 0 ? 16 / 9 : abs(size.width / size.height)
        } catch {
            log.error("Could not load video: \(error.localizedDescription, privacy: .public)")
            return false
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        range = TrimRange(duration: duration)
        cuts = CutList()
        selection = nil
        undoStack = UndoStack()
        currentTime = 0
        thumbnails = []
        applyRange()
        return true
    }

    func teardown() {
        player.pause()
        for observer in [timeObserver, cutObserver].compactMap(\.self) {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        cutObserver = nil
        statusObservation = nil
    }

    // MARK: Trimming

    /// Call when a drag on the timeline starts; `endDrag` records one undo step if the range changed.
    func beginDrag() {
        dragOrigin = range
        player.pause()
    }

    /// The handles stop where the cuts would leave too little to play.
    func drag(_ handle: TrimHandle, to time: Double) {
        let moved = range.moving(handle, to: time, duration: duration)
        if cuts.allows(moved) {
            range = moved
        }
        seek(to: handle == .start ? range.start : range.end)
    }

    func endDrag() {
        if let dragOrigin, dragOrigin != range {
            undoStack.record(VideoEdit(range: dragOrigin, cuts: cuts, options: options))
        }
        dragOrigin = nil
        applyRange()
    }

    // MARK: Cutting

    /// Marks the section between `anchor` and `time` and shows the frame at `time`.
    func select(from anchor: Double, to time: Double) {
        player.pause()
        let ends = [anchor, time].map { min(max($0, 0), duration) }
        selection = ends[0] == ends[1] ? nil : ends.min()!..<ends.max()!
        seek(to: ends[1])
    }

    /// False when nothing was selected.
    @discardableResult
    func clearSelection() -> Bool {
        defer { selection = nil }
        return selection != nil
    }

    /// Cuts the selection out as one undo step; false when nothing is selected.
    func cutSelection() -> Bool {
        guard let selection, !isExporting else {
            return false
        }
        self.selection = nil
        guard let cut = cuts.cutting(selection, from: range) else {
            Toast.show("Can't cut all of the video")
            return true
        }
        if cut != cuts {
            undoStack.record(edit)
            cuts = cut
            applyRange()
        }
        return true
    }

    func setOptions(_ new: VideoExportOptions) {
        guard new != options else {
            return
        }
        undoStack.record(edit)
        options = new
        Preferences.remember(options)
    }

    /// Undo and redo wait for an export, since Save reloads the file and would drop the change.
    func undo() {
        if !isExporting, let previous = undoStack.undo(from: edit) {
            restore(previous)
        }
    }

    func redo() {
        if !isExporting, let next = undoStack.redo(from: edit) {
            restore(next)
        }
    }

    private func restore(_ edit: VideoEdit) {
        range = edit.range
        cuts = edit.cuts
        if options != edit.options {
            options = edit.options
            Preferences.remember(options)
        }
        applyRange()
    }

    /// Playback jumps over the cuts and stops at the end of the last section.
    private func applyRange() {
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: cuts.playbackEnd(in: range), preferredTimescale: 600)
        if let cutObserver {
            player.removeTimeObserver(cutObserver)
        }
        cutObserver = nil
        guard !cuts.isEmpty else {
            return
        }
        let starts = cuts.cuts.map { NSValue(time: CMTime(seconds: $0.lowerBound, preferredTimescale: 600)) }
        cutObserver = player.addBoundaryTimeObserver(forTimes: starts, queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                self?.skipCut()
            }
        }
    }

    /// The boundary observer fires at or just after a cut's start.
    private func skipCut() {
        if let cut = cuts.cut(containing: player.currentTime().seconds + 0.05) {
            seek(to: cut.upperBound)
        }
    }

    // MARK: Playback

    func togglePlay() {
        if isPlaying {
            player.pause()
            return
        }
        let start = cuts.playbackStart(from: currentTime, in: range)
        if start != currentTime {
            seek(to: start)
        }
        player.play()
    }

    func step(_ frames: Int) {
        player.pause()
        player.currentItem?.step(byCount: frames)
    }

    func seek(to time: Double) {
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func loadThumbnails(count: Int, height: CGFloat) async {
        let times = TrimTimeline(duration: duration, minX: 0, width: 0).thumbnailTimes(count: count)
        thumbnails = Array(repeating: nil, count: times.count)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: height * aspectRatio * 2, height: height * 2)
        for (index, time) in times.enumerated() {
            let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            // A newer load (resize, or reload after a save) may have replaced the array while this one waited.
            guard !Task.isCancelled, index < thumbnails.count else {
                return
            }
            thumbnails[index] = image
        }
    }

    // MARK: Output

    /// Copies the file, or an edited copy of it, to the clipboard.
    func copy() async {
        guard isDirty else {
            Clipboard.copy(fileURL: fileURL)
            Toast.show("Copied")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shot/\(UUID().uuidString)")
        let output = folder.appendingPathComponent(fileURL.lastPathComponent)
        guard await export(to: output, creating: folder) else {
            return
        }
        Clipboard.copy(fileURL: output)
        Toast.show("Copied")
    }

    /// Replaces the file with the trimmed range, less the cuts, and copies it, like Save in the image editor.
    @discardableResult
    func save() async -> Bool {
        guard isDirty else {
            Toast.show("Trim or cut the video first")
            return false
        }
        let replacements: URL
        do {
            replacements = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: fileURL, create: true)
        } catch {
            Toast.show("Save failed: \(error.localizedDescription)")
            return false
        }
        defer { try? FileManager.default.removeItem(at: replacements) }
        let trimmed = replacements.appendingPathComponent(fileURL.lastPathComponent)
        guard await export(to: trimmed, creating: nil) else {
            return false
        }
        do {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: trimmed)
        } catch {
            Toast.show("Save failed: \(error.localizedDescription)")
            return false
        }
        log.notice("Saved edited video: \(self.fileURL.path)")
        Clipboard.copy(fileURL: fileURL)
        Toast.show("Saved and copied")
        _ = await load()
        return true
    }

    /// Writes a new file next to the original with the trim, cuts and export options, and copies it.
    func export() async {
        // Checked before picking a name, so two exports can't pick the same one.
        guard !isExporting else {
            return
        }
        let options = options, range = range, cuts = cuts, source = fileURL
        let output = FileNaming.uniqueURL(in: source.deletingLastPathComponent(), date: Date(), pathExtension: options.format.fileExtension, prefix: Preferences().filePrefix)
        var note = ""
        let exported = await exporting {
            switch options.format {
            case .mp4:
                let passthrough = try await VideoTrimmer.trim(source, range: range, cuts: cuts, speed: options.speed, muted: options.muted, to: output, as: .mp4)
                log.notice("Exported MP4 at \(options.speed, privacy: .public)×, muted \(options.muted, privacy: .public), passthrough \(passthrough, privacy: .public)")
            case .gif:
                let result = try await GIFExporter.export(
                    videoURL: source, to: output, range: range, cuts: cuts, fps: Double(options.gifFrameRate), maxWidth: options.gifMaxWidth, speed: options.speed
                ) { fraction in
                    Task { @MainActor in
                        Toast.show("Exporting… \(Int(fraction * 100))%", duration: nil)
                    }
                }
                note = result.truncated ? " (first \(Int(GIFExporter.maxDuration)) s only)" : ""
                log.notice("Exported GIF: \(result.frameCount, privacy: .public) frames at \(options.gifFrameRate, privacy: .public) fps, width \(options.gifWidth, privacy: .public), \(options.speed, privacy: .public)×")
            }
        }
        guard exported else {
            try? FileManager.default.removeItem(at: output)
            return
        }
        Clipboard.copy(fileURL: output)
        Toast.show("Exported and copied \(output.lastPathComponent)\(note)", duration: .seconds(3))
    }

    /// Works out `estimatedSize` for the current trim, cuts and options; call again when any change.
    func refreshEstimate() async {
        let options = options, range = range, cuts = cuts, source = fileURL
        // Wait for a drag or a run of clicks to settle before reading frames.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else {
            return
        }
        do {
            let size = switch options.format {
            case .mp4:
                try await VideoTrimmer.estimatedSize(of: source, range: range, cuts: cuts, speed: options.speed, muted: options.muted)
            case .gif:
                try await GIFExporter.estimatedSize(of: source, range: range, cuts: cuts, fps: Double(options.gifFrameRate), maxWidth: options.gifMaxWidth, speed: options.speed)
            }
            if !Task.isCancelled {
                estimatedSize = size
            }
        } catch is CancellationError {
            return
        } catch {
            log.error("Size estimate failed: \(error.localizedDescription, privacy: .public)")
            estimatedSize = nil
        }
    }

    private func export(to output: URL, creating folder: URL?) async -> Bool {
        await exporting {
            if let folder {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let passthrough = try await VideoTrimmer.trim(fileURL, range: range, cuts: cuts, to: output)
            log.notice("Trimmed \(self.range.start, privacy: .public)–\(self.range.end, privacy: .public) s less \(self.cuts.cuts.count, privacy: .public) cuts, passthrough \(passthrough, privacy: .public)")
        }
    }

    /// Runs `work` with the player paused, one export at a time; false if it couldn't start or failed.
    private func exporting(_ work: () async throws -> Void) async -> Bool {
        guard !isExporting else {
            return false
        }
        isExporting = true
        defer { isExporting = false }
        player.pause()
        Toast.show("Exporting…", duration: nil)
        do {
            try await work()
            return true
        } catch {
            log.error("Export failed: \(error.localizedDescription, privacy: .public)")
            Toast.show("Export failed: \(error.localizedDescription)", duration: .seconds(3))
            return false
        }
    }
}
