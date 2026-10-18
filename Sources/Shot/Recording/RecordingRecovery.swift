import AVFoundation
import os
import ShotCoreApple

private let log = Logger.shot("recording")

/// Rescuing what a recording that never finished left behind, rather than throwing it away.
extension Recorder {
    /// Whether AVFoundation can read a duration and a picture from `url`, which a segment cut short by a crash or a full disk may not have.
    nonisolated static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0,
              let video = try? await asset.loadTracks(withMediaType: .video), !video.isEmpty
        else {
            return false
        }
        return true
    }

    /// Where a recovered recording goes. Always the save folder: with saving off the capture folder is temporary and cleaned up.
    private nonisolated static func recoveryFolder() throws -> URL {
        let folder = Preferences().saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Moves `parts` to the save folder as separate files, when they couldn't be joined. Returns where they went, or nil if none could move.
    nonisolated static func keepAsIs(_ parts: [URL], date: Date) async -> [URL]? {
        guard let folder = try? recoveryFolder() else {
            return nil
        }
        let prefix = Preferences().filePrefix
        var kept: [URL] = []
        for (index, part) in parts.enumerated() {
            let target = FileNaming.recoveredURL(in: folder, date: date, part: parts.count > 1 ? index + 1 : nil, prefix: prefix)
            do {
                try FileManager.default.moveItem(at: part, to: target)
                kept.append(target)
            } catch {
                log.error("Couldn't keep \(part.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return kept.isEmpty ? nil : kept
    }

    /// Joins or saves the segments a recording left in the temporary folder when it never finished, a crash or quit say.
    /// Call at launch, before anything records. What it recovers goes to the save folder as "… (recovered).mp4" with a
    /// toast to show it; the rest, files that are empty or unreadable, is deleted. Files written in the last ten minutes
    /// are left alone, in case another copy of Shot is recording into the same folder.
    nonisolated static func recoverLeftoverSegments() async {
        let folder = segmentsFolder
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        let files = found.map { SegmentRecovery.File(name: $0.lastPathComponent, modified: (try? $0.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast) }
        let plan = SegmentRecovery.plan(files)
        func remove(_ names: [String]) {
            for name in names {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        remove(plan.orphans)
        var playable: [SegmentRecovery.Segment] = []
        for segment in plan.segments {
            if await isPlayable(folder.appendingPathComponent(segment.video)) {
                playable.append(segment)
            } else {
                remove(segment.files)
            }
        }
        log.notice("Leftover segments: \(playable.count) to recover, \(plan.segments.count - playable.count + plan.orphans.count) swept")
        guard let first = playable.first, let saveFolder = try? recoveryFolder() else {
            return
        }
        let videos = playable.map { folder.appendingPathComponent($0.video) }
        let audio = SegmentRecovery.audio(of: playable)?.map {
            VideoConcatenator.SegmentAudio(system: folder.appendingPathComponent($0.system), microphone: folder.appendingPathComponent($0.microphone))
        }
        let output = FileNaming.recoveredURL(in: saveFolder, date: first.modified, prefix: Preferences().filePrefix)
        // The audio files only let the microphone be muted, so if they're what stops a join, the segments' own audio will do.
        for attempt in audio.map({ [$0, []] }) ?? [[]] {
            do {
                try await VideoConcatenator.concatenate(videos, audio: attempt, to: output)
                remove(playable.flatMap(\.files))
                log.notice("Recovered \(playable.count) segments to \(output.path, privacy: .public)")
                await MainActor.run { Toast.show("Recovered an interrupted recording", duration: .seconds(8), reveal: output) }
                return
            } catch {
                log.error("Joining leftover segments failed: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: output)
            }
        }
        let remaining = videos.filter { FileManager.default.fileExists(atPath: $0.path) }
        if let kept = await keepAsIs(remaining, date: first.modified) {
            await MainActor.run { Toast.show("Saved the parts of an interrupted recording", duration: .seconds(8), reveal: kept[0]) }
        }
    }
}
