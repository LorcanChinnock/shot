import AppKit
import AVFoundation
import Observation
import os
import ShotCore

private let log = Logger.shot("video-editor")

@MainActor
@Observable
final class VideoEditorModel {
    let fileURL: URL
    let player = AVPlayer()
    private(set) var duration: Double = 0
    private(set) var aspectRatio: CGFloat = 16 / 9
    private(set) var range = TrimRange(duration: 0)
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var isExporting = false
    private(set) var thumbnails: [CGImage?] = []
    private(set) var undoStack = UndoStack<TrimRange>()

    @ObservationIgnored private var dragOrigin: TrimRange?
    @ObservationIgnored private var timeObserver: Any?
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

    var isDirty: Bool { !range.isFull(duration: duration) }

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
        undoStack = UndoStack()
        currentTime = 0
        thumbnails = []
        applyRange()
        return true
    }

    func teardown() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation = nil
    }

    // MARK: Trimming

    /// Call when a drag on the timeline starts; `endDrag` records one undo step if the range changed.
    func beginDrag() {
        dragOrigin = range
        player.pause()
    }

    func drag(_ handle: TrimHandle, to time: Double) {
        range = range.moving(handle, to: time, duration: duration)
        seek(to: handle == .start ? range.start : range.end)
    }

    func endDrag() {
        if let dragOrigin, dragOrigin != range {
            undoStack.record(dragOrigin)
        }
        dragOrigin = nil
        applyRange()
    }

    func undo() {
        if let previous = undoStack.undo(from: range) {
            range = previous
            applyRange()
        }
    }

    func redo() {
        if let next = undoStack.redo(from: range) {
            range = next
            applyRange()
        }
    }

    /// Playback stops at the out point.
    private func applyRange() {
        player.currentItem?.forwardPlaybackEndTime = range.timeRange.end
    }

    // MARK: Playback

    func togglePlay() {
        if isPlaying {
            player.pause()
            return
        }
        let start = range.playbackStart(from: currentTime)
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
            guard !Task.isCancelled, let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image else {
                return
            }
            thumbnails[index] = image
        }
    }

    // MARK: Output

    /// Copies the file, or a trimmed copy of it, to the clipboard.
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

    /// Replaces the file with the trimmed range and copies it, like Save in the image editor.
    @discardableResult
    func save() async -> Bool {
        guard isDirty else {
            Toast.show("Drag the handles to trim")
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
        log.notice("Saved trimmed video: \(self.fileURL.path)")
        Clipboard.copy(fileURL: fileURL)
        Toast.show("Saved and copied")
        _ = await load()
        return true
    }

    private func export(to output: URL, creating folder: URL?) async -> Bool {
        guard !isExporting else {
            return false
        }
        isExporting = true
        defer { isExporting = false }
        player.pause()
        Toast.show("Exporting…", duration: nil)
        do {
            if let folder {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let passthrough = try await VideoTrimmer.trim(fileURL, range: range, to: output)
            log.notice("Trimmed \(self.range.start, privacy: .public)–\(self.range.end, privacy: .public) s, passthrough \(passthrough, privacy: .public)")
            return true
        } catch {
            log.error("Trim failed: \(error.localizedDescription, privacy: .public)")
            Toast.show("Export failed: \(error.localizedDescription)", duration: .seconds(3))
            return false
        }
    }
}
