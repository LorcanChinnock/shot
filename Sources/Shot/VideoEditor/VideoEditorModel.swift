import AppKit
import AVFoundation
import Observation
import os
import ShotCore

private let log = Logger.shot("video-editor")

/// What one undo step restores.
struct VideoEdit: Equatable {
    var project: Project
    var options: VideoExportOptions
}

@MainActor
@Observable
final class VideoEditorModel {
    let fileURL: URL
    let player = AVPlayer()
    private(set) var duration: Double = 0
    private(set) var aspectRatio: CGFloat = 16 / 9
    /// The edit: the recording on the main track, trimmed and cut, and anything imported. Everything below is read from it.
    private(set) var project: Project {
        didSet {
            // The lanes keep their scale as the project shrinks, so trimming doesn't stretch what's left.
            // Mid-drag the scale holds, so a clip dragged past the end doesn't shrink the lanes under the pointer.
            if dragOrigin == nil {
                fitDuration = max(fitDuration, project.duration)
            }
            projectDidChange()
        }
    }
    /// The length one screen width of lanes covers at zoom 1: the longest the project has been.
    private(set) var fitDuration: Double = 0
    /// The section a Shift-drag on the timeline marked, on the timeline, which Delete cuts.
    private(set) var selection: Range<Double>?
    /// The player's own time: the recording's while it plays the file, the timeline's while it plays the composite.
    private(set) var currentTime: Double = 0
    /// Whether the player has the composite of every track, not just the recording with its cuts skipped.
    private(set) var itemIsComposite = false
    private(set) var isPlaying = false
    var isExporting: Bool { exportTask != nil }
    private var exportTask: Task<Bool, Never>?
    private(set) var thumbnailSets: [URL: [CGImage?]] = [:]
    @ObservationIgnored private var thumbnailSources: [URL: ThumbnailSource] = [:]
    /// Applies to Export only; Copy and Save keep the original format, speed and sound.
    private(set) var options = Preferences().videoExportOptions
    /// Bytes Export would write, or nil until it's worked out.
    private(set) var estimatedSize: Int?
    private(set) var undoStack = UndoStack<VideoEdit>()

    // Tracks panel
    private(set) var showsTracks = UserDefaults.standard.bool(forKey: VideoEditorModel.showsTracksKey)
    /// 1 fits the project in the window; see `TimelineZoom`.
    private(set) var zoom: Double = 1
    private(set) var snapping = true
    /// The clip the Split, Delete and transform handles act on.
    private(set) var selectedClipID: UUID? {
        didSet {
            if selectedClipID != oldValue {
                selectedKeyframe = nil
            }
        }
    }
    /// The time of the keyframe being worked on, in seconds from the start of the selected clip.
    private(set) var selectedKeyframe: Double?
    private(set) var showsLayers = UserDefaults.standard.bool(forKey: VideoEditorModel.showsLayersKey)
    private(set) var showsInspector = UserDefaults.standard.bool(forKey: VideoEditorModel.showsInspectorKey)
    private(set) var waveforms: [URL: Waveform] = [:]
    /// The tool drawing annotations over the video, or nil when none is picked. Never crop.
    private(set) var annotationTool: EditorTool?
    var annotationStyle = Preferences().editorStyle
    /// The text or note whose text field is open, with the colour and size picked for it so far; it may not be on the timeline yet.
    var editingText: Annotation?
    /// Called when the panel opens, closes or changes height, so the window can grow or shrink to fit.
    @ObservationIgnored var onLayoutChanged: (() -> Void)?

    private static let showsTracksKey = "videoEditorShowsTracks"
    private static let showsInspectorKey = "videoEditorShowsInspector"
    private static let showsLayersKey = "videoEditorShowsLayers"

    @ObservationIgnored private var dragOrigin: Project?
    /// Where in the recording the playhead was before a trim handle drag moved it to show the edge.
    @ObservationIgnored private var trimResume: Double?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    /// What the compositor draws over the project's own annotations while one is being edited.
    @ObservationIgnored private var liveState: (hidden: Set<UUID>, drawn: [AnnotationClip]) = ([], [])
    @ObservationIgnored private var compositeLive: LiveAnnotations?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var cutObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init(fileURL: URL) {
        self.fileURL = fileURL
        project = Project(source: fileURL, duration: 0, canvasSize: .zero, hasAudio: false)
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

    /// The trim handles and cuts the project reduces to; Copy, Save and Export all write these.
    private var trim: TrimEdit? { project.trimEdit }

    var range: TrimRange { trim?.range ?? TrimRange(duration: duration) }

    /// Sections removed from inside `range`.
    var cuts: CutList { trim?.cuts ?? CutList() }

    /// Whether the edit is more than a trim and cuts of the recording, so it has to be drawn and re-encoded.
    var isComposite: Bool { project.trimEdit == nil }

    /// Where the playhead is on the timeline, which differs from the recording's time once something's cut.
    var playhead: Double { itemIsComposite ? currentTime : project.timelinePosition(ofSource: currentTime) }

    var thumbnails: [CGImage?] { thumbnailSets[fileURL] ?? [] }

    var selectedClip: Clip? { selectedClipID.flatMap(project.clip) }

    var isDirty: Bool { isComposite || !range.isFull(duration: duration) || !cuts.isEmpty }

    /// What the panel adds to the window's height over the collapsed layout.
    var tracksExtraHeight: CGFloat {
        guard showsTracks else {
            return 0
        }
        let palette = isAnnotating ? AnnotationPalette.height + Brutal.sectionGap : 0
        let inspector = showsInspector ? ClipInspector.height + Brutal.sectionGap : 0
        return TracksView.extraHeight(for: project) + palette + inspector
    }

    var edit: VideoEdit { VideoEdit(project: project, options: options) }

    /// How long Copy and Save run for: the range less the cuts.
    var keptLength: Double { project.duration }

    /// Loads (or reloads, after a save) the file; throws a readable reason when it has no video to show.
    func load() async throws {
        let asset = AVURLAsset(url: fileURL)
        do {
            let duration = try await asset.load(.duration).seconds
            guard duration > 0 else {
                throw LoadFailure(reason: "it has no length")
            }
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw LoadFailure(reason: "it has no video track")
            }
            let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
            let size = naturalSize.applying(transform)
            let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
            self.duration = duration
            aspectRatio = size.height == 0 ? 16 / 9 : abs(size.width / size.height)
            project = Project(source: fileURL, duration: duration, canvasSize: CGSize(width: abs(size.width), height: abs(size.height)), hasAudio: hasAudio)
        } catch let failure as LoadFailure {
            throw failure
        } catch {
            log.error("Could not load video: \(error.localizedDescription, privacy: .public)")
            throw LoadFailure(reason: "it isn't a video Shot can read")
        }
        rebuildTask?.cancel()
        itemIsComposite = false
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        fitDuration = project.duration
        selection = nil
        selectedClipID = nil
        undoStack = UndoStack()
        currentTime = 0
        thumbnailSets = [:]
        thumbnailSources = [:]
        waveforms = [:]
        applyRange()
    }

    struct LoadFailure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    func teardown() {
        rebuildTask?.cancel()
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
        dragOrigin = project
        player.pause()
    }

    /// The handles stop where the cuts would leave too little to play.
    func drag(_ handle: TrimHandle, to time: Double) {
        if trimResume == nil {
            trimResume = project.sourceTime(atTimeline: playhead)
        }
        if let moved = dragOrigin?.trimmingMain(handle, toSource: time) {
            project = moved
        }
        guard !itemIsComposite else {
            seekTimeline(to: handle == .start ? 0 : project.duration)
            return
        }
        seek(to: handle == .start ? range.start : range.end)
    }

    func endDrag() {
        let origin = dragOrigin
        dragOrigin = nil
        if let resume = trimResume {
            trimResume = nil
            seekTimeline(to: project.timelinePosition(ofSource: resume))
        }
        // A drag that only scrubbed leaves the player alone.
        guard let origin, origin != project else {
            return
        }
        undoStack.record(VideoEdit(project: origin, options: options))
        fitDuration = max(fitDuration, project.duration)
        projectDidChange()
    }

    /// Drags a clip that isn't on the main track so it starts at timeline `time`; call between `beginDrag` and `endDrag`.
    func moveClip(_ id: UUID, toStart time: Double, snapThreshold threshold: Double) {
        let snap = snapping ? threshold : nil
        if let moved = dragOrigin?.moving(clip: id, toStart: time, snapWithin: snap, snapTo: [playhead]) {
            project = moved
        }
    }

    /// Drags an edge of a clip that isn't on the main track to timeline `time`; call between `beginDrag` and `endDrag`.
    func trimClip(_ id: UUID, _ edge: TrimHandle, toTimeline time: Double, snapThreshold threshold: Double) {
        let snap = snapping ? threshold : nil
        if let trimmed = dragOrigin?.trimming(clip: id, edge, toTimeline: time, snapWithin: snap, snapTo: [playhead]) {
            project = trimmed
        }
    }

    // MARK: Tracks

    /// A project with more than a trim in it has no strip to go back to.
    var canHideTracks: Bool { !(showsTracks && isComposite) }

    func toggleTracks() {
        guard canHideTracks else {
            Toast.error("Delete the imported clips and transforms to hide the tracks")
            return
        }
        setShowsTracks(!showsTracks)
    }

    private func setShowsTracks(_ shown: Bool) {
        guard shown != showsTracks else {
            return
        }
        showsTracks = shown
        UserDefaults.standard.set(shown, forKey: Self.showsTracksKey)
        onLayoutChanged?()
    }

    func toggleSnapping() {
        snapping.toggle()
    }

    func zoom(bySteps steps: Int) {
        zoom = TimelineZoom.zoomed(zoom, bySteps: steps)
    }

    func resetZoom() {
        zoom = 1
    }

    func setZoom(_ new: Double) {
        zoom = min(max(new, TimelineZoom.range.lowerBound), TimelineZoom.range.upperBound)
    }

    func selectClip(_ id: UUID?) {
        selectedClipID = id
    }

    func selectClip(at time: Double?) {
        selectedClipID = time.flatMap { project.mainClip(at: $0)?.id }
    }

    /// Moves the playhead to timeline `time`, snapping to a clip edge within `threshold` seconds when snapping is on.
    func scrub(toTimeline time: Double, snapThreshold threshold: Double) {
        var target = min(max(time, 0), project.duration)
        if snapping, let snapped = Snapping.snap(target, to: project.snapPoints(), within: threshold) {
            target = snapped
        }
        seekTimeline(to: target)
    }

    /// Splits the clips under the playhead; false when it's on a clip's edge.
    @discardableResult
    func split() -> Bool {
        guard !isExporting, let split = project.splitting(at: playhead) else {
            return false
        }
        undoStack.record(edit)
        project = split
        return true
    }

    /// Turns a track's lock, hide or mute on or off as one undo step.
    func toggle(_ flag: WritableKeyPath<Track, Bool>, ofTrack index: Int) {
        guard !isExporting, project.tracks.indices.contains(index) else {
            return
        }
        undoStack.record(edit)
        project.tracks[index][keyPath: flag].toggle()
    }

    // MARK: Layers

    /// The overlay tracks, topmost first, as the layers panel lists them.
    var layerRows: [LayerRow] {
        project.overlayTracks.reversed().map { track in
            LayerRow(id: track.id, name: track.layerName, symbol: track.annotations.first?.annotation.layerSymbol ?? "square.dashed", isHidden: track.isHidden, isLocked: track.isLocked)
        }
    }

    /// The track of the selected annotation clip.
    var selectedLayerIDs: Set<UUID> {
        guard let id = selectedClipID, let track = project.tracks.first(where: { $0.kind == .overlay && $0.annotations.contains { $0.id == id } }) else {
            return []
        }
        return [track.id]
    }

    func toggleLayers() {
        showsLayers.toggle()
        UserDefaults.standard.set(showsLayers, forKey: Self.showsLayersKey)
    }

    /// Selects the annotation showing at the playhead on the picked track, else its first. A track is one row however many clips it holds.
    func selectLayers(_ ids: Set<UUID>) {
        let picked = ids.subtracting(selectedLayerIDs).first ?? ids.first
        guard let track = project.tracks.first(where: { $0.id == picked }) else {
            selectedClipID = nil
            return
        }
        selectedClipID = (track.annotations.first { $0.start <= playhead && playhead < $0.end } ?? track.annotations.first)?.id
    }

    /// Applies `change` as one undo step, or does nothing if it leaves the project as it was.
    private func editLayers(_ change: (Project) -> Project) {
        guard !isExporting else {
            return
        }
        let changed = change(project)
        guard changed != project else {
            return
        }
        undoStack.record(edit)
        project = changed
    }

    func moveSelectedLayers(_ move: LayerMove) {
        let ids = selectedLayerIDs
        editLayers { $0.movingOverlays(ids, move) }
    }

    func moveLayers(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let listed = layerRows
        let moved = Set(offsets.map { listed[$0].id })
        let index = LayerList.backToFrontIndex(movingOffsets: offsets, toOffset: destination, count: listed.count)
        editLayers { $0.movingOverlays(moved, toIndex: index) }
    }

    func setLayersHidden(_ hidden: Bool, _ ids: Set<UUID>) {
        editLayers { $0.setting(\.isHidden, to: hidden, ofOverlays: ids) }
    }

    func setLayersLocked(_ locked: Bool, _ ids: Set<UUID>) {
        editLayers { $0.setting(\.isLocked, to: locked, ofOverlays: ids) }
    }

    func deleteLayers(_ ids: Set<UUID>) {
        if !selectedLayerIDs.isDisjoint(with: ids) {
            selectedClipID = nil
        }
        editLayers { project in
            let unlocked = ids.filter { id in project.tracks.first { $0.id == id }?.isLocked == false }
            return project.deletingOverlays(unlocked)
        }
    }

    /// Cuts the selected clip out, closing the gap on the main track, as one undo step; false when none is selected.
    func deleteSelectedClip() -> Bool {
        guard let id = selectedClipID, !isExporting else {
            return false
        }
        selectedClipID = nil
        guard let cut = project.deleting(clip: id) else {
            Toast.error(project.clip(id).map { _ in "Can't delete this clip" } ?? "Can't cut all of the video")
            return true
        }
        let joinedAt = project.main.clips.first { $0.id == id }?.start ?? playhead
        undoStack.record(edit)
        project = cut
        seekTimeline(to: min(joinedAt, project.duration))
        return true
    }

    // MARK: Importing

    /// Puts each file on new tracks at the playhead, or after the main track when `appendToMain` is set.
    func importMedia(_ urls: [URL], appendToMain: Bool = false) async {
        guard !isExporting else {
            return
        }
        var changed = project
        var added: UUID?
        for url in urls {
            do {
                let media = try await MediaProbe.probe(url)
                let result = appendToMain ? changed.appending(media) : changed.importing(media, at: playhead)
                guard let result else {
                    Toast.error("Can't add \(url.lastPathComponent) there")
                    continue
                }
                changed = result.project
                added = result.clip
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
        guard let added else {
            return
        }
        undoStack.record(edit)
        project = changed
        selectedClipID = added
        setShowsTracks(true)
        log.notice("Imported \(urls.count, privacy: .public) files")
    }

    // MARK: Waveforms

    func loadWaveform(for source: URL) async {
        guard waveforms[source] == nil, let waveform = try? await Waveform.load(source) else {
            return
        }
        waveforms[source] = waveform
    }

    // MARK: Cutting

    /// Marks the section between two times in the recording and shows the frame at the second.
    func select(fromSource anchor: Double, toSource time: Double) {
        let ends = [anchor, time].map { min(max($0, 0), duration) }
        select(fromTimeline: project.timelinePosition(ofSource: ends[0]), toTimeline: project.timelinePosition(ofSource: ends[1]))
        seek(to: ends[1])
    }

    /// Marks the section between `anchor` and `time` on the timeline and shows the frame at `time`.
    func select(fromTimeline anchor: Double, toTimeline time: Double) {
        player.pause()
        let ends = [anchor, time].map { min(max($0, 0), project.duration) }
        selection = ends[0] == ends[1] ? nil : ends.min()!..<ends.max()!
        seekTimeline(to: ends[1])
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
        guard let cut = project.deleting(range: selection) else {
            Toast.error("Can't cut all of the video")
            return true
        }
        if cut != project {
            undoStack.record(edit)
            project = cut
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
        project = edit.project
        selection = nil
        if let selectedClipID, project.clip(selectedClipID) == nil {
            self.selectedClipID = nil
        }
        if options != edit.options {
            options = edit.options
            Preferences.remember(options)
        }
    }

    /// Brings the player and the window up to date with the project, once nothing is being dragged.
    private func projectDidChange() {
        guard dragOrigin == nil else {
            return
        }
        onLayoutChanged?()
        refreshPlayer()
    }

    /// Plays the composite while the edit needs drawing, or an annotation is being drawn; the recording itself otherwise.
    private func refreshPlayer() {
        guard dragOrigin == nil else {
            return
        }
        if isComposite || isAnnotating {
            rebuildComposite()
        } else if itemIsComposite {
            reloadRecording()
        } else {
            applyRange()
        }
    }

    /// Plays the composite of every track in place of the recording, from where the playhead was.
    private func rebuildComposite() {
        rebuildTask?.cancel()
        let snapshot = project
        rebuildTask = Task {
            // A run of edits builds once.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else {
                return
            }
            do {
                let built = try await CompositionBuilder.build(snapshot)
                guard !Task.isCancelled else {
                    return
                }
                let resume = playhead
                let item = AVPlayerItem(asset: built.asset)
                item.videoComposition = built.videoComposition
                item.audioMix = built.audioMix
                player.pause()
                removeCutObserver()
                itemIsComposite = true
                player.replaceCurrentItem(with: item)
                seekTimeline(to: min(resume, built.duration))
                // The project has the finished edit now, so what stood in for it can go.
                liveState = ([], [])
                compositeLive = built.live
            } catch {
                log.error("Could not build the composite: \(error.localizedDescription, privacy: .public)")
                Toast.error("Could not show the edit: \(error.localizedDescription)")
            }
        }
    }

    /// Goes back to playing the recording itself, once the edit is only a trim and cuts again.
    private func reloadRecording() {
        rebuildTask?.cancel()
        let resume = playhead
        player.pause()
        itemIsComposite = false
        player.replaceCurrentItem(with: AVPlayerItem(url: fileURL))
        applyRange()
        seekTimeline(to: resume)
    }

    private func removeCutObserver() {
        if let cutObserver {
            player.removeTimeObserver(cutObserver)
        }
        cutObserver = nil
    }

    /// Playback jumps over the cuts and stops at the end of the last section.
    private func applyRange() {
        guard !itemIsComposite else {
            return
        }
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: cuts.playbackEnd(in: range), preferredTimescale: 600)
        if let cutObserver {
            player.removeTimeObserver(cutObserver)
        }
        cutObserver = nil
        let starts = cuts.skipPoints(in: range)
        guard !starts.isEmpty else {
            return
        }
        cutObserver = player.addBoundaryTimeObserver(forTimes: starts.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }, queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                self?.skipCut()
            }
        }
    }

    private func skipCut() {
        if let cut = cuts.cut(reachedAt: player.currentTime().seconds) {
            seek(to: cut.upperBound)
        }
    }

    // MARK: Playback

    func togglePlay() {
        if isPlaying {
            player.pause()
            return
        }
        if itemIsComposite {
            if playhead >= project.duration - 0.02 {
                seek(to: 0)
            }
        } else {
            let start = cuts.playbackStart(from: currentTime, in: range)
            if start != currentTime {
                seek(to: start)
            }
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

    /// Moves the playhead to timeline `time`, in whichever time the player is in.
    func seekTimeline(to time: Double) {
        seek(to: itemIsComposite ? time : project.sourceTime(atTimeline: time))
    }

    /// Moves the playhead by `seconds` along the timeline, for VoiceOver's adjust gesture.
    func nudgePlayhead(bySeconds seconds: Double) {
        seekTimeline(to: min(max(0, playhead + seconds), keptLength))
    }

    /// Thumbnails of the recording for the strip.
    func loadThumbnails(count: Int, height: CGFloat) async {
        await loadThumbnails(of: fileURL, duration: duration, aspectRatio: aspectRatio, count: count, height: height)
    }

    /// `count` frames from equal slots of `source`, `height` points tall, into `thumbnailSets`. Frames fetched before are reused.
    func loadThumbnails(of source: URL, duration: Double, aspectRatio: CGFloat, count: Int, height: CGFloat) async {
        let times = TrimTimeline(duration: duration, minX: 0, width: 0).thumbnailTimes(count: count)
        let size = CGSize(width: height * aspectRatio * 2, height: height * 2)
        if thumbnailSources[source]?.generator.maximumSize != size {
            thumbnailSources[source] = ThumbnailSource(url: source, maximumSize: size)
        }
        guard let fetcher = thumbnailSources[source] else {
            return
        }
        let cached = fetcher.cache.frames(for: times, spacing: duration / Double(times.count))
        // Until each new frame arrives the old one nearest in time stands in, so zooming doesn't flash black.
        let old = thumbnailSets[source] ?? []
        var frames = times.indices.map { cached[$0] ?? (old.isEmpty ? nil : old[min(old.count - 1, $0 * old.count / times.count)]) }
        thumbnailSets[source] = frames
        let missing = times.indices.filter { cached[$0] == nil }
        guard !missing.isEmpty else {
            return
        }
        let requested = missing.map { CMTime(seconds: times[$0], preferredTimescale: 600) }
        var lastWrite = ContinuousClock.now
        var unwritten = false
        for await result in fetcher.generator.images(for: requested) {
            // A newer load (resize, or reload after a save) may have replaced the array while this one waited.
            guard !Task.isCancelled, thumbnailSets[source]?.count == frames.count else {
                return
            }
            guard let position = requested.firstIndex(of: result.requestedTime), let image = try? result.image else {
                continue
            }
            let index = missing[position]
            fetcher.cache.insert(image, at: times[index])
            frames[index] = image
            unwritten = true
            // Each write redraws the lanes, so frames go in a few at a time.
            if ContinuousClock.now - lastWrite > .milliseconds(100) {
                thumbnailSets[source] = frames
                lastWrite = .now
                unwritten = false
            }
        }
        if unwritten, !Task.isCancelled, thumbnailSets[source]?.count == frames.count {
            thumbnailSets[source] = frames
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
            try? FileManager.default.removeItem(at: folder)
            return
        }
        Clipboard.copy(fileURL: output)
        Toast.show("Copied")
    }

    /// Replaces the file with the trimmed range, less the cuts, and copies it, like Save in the image editor.
    /// An edit with imports or transforms is written as a copy next to the file, since the recording itself stays as it was.
    @discardableResult
    func save() async -> Bool {
        guard isDirty else {
            Toast.error("Trim or cut the video first")
            return false
        }
        if isComposite {
            return await saveCopy()
        }
        let replacements: URL
        do {
            replacements = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: fileURL, create: true)
        } catch {
            Toast.error("Save failed: \(error.localizedDescription)")
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
            Toast.error("Save failed: \(error.localizedDescription)")
            return false
        }
        log.notice("Saved edited video: \(self.fileURL.path)")
        Clipboard.copy(fileURL: fileURL)
        Toast.show("Saved and copied")
        try? await load()
        return true
    }

    private func saveCopy() async -> Bool {
        guard !isExporting else {
            return false
        }
        let output = FileNaming.uniqueURL(in: fileURL.deletingLastPathComponent(), date: Date(), pathExtension: Self.copyExtension(of: fileURL), prefix: Preferences().filePrefix)
        guard await export(to: output, creating: nil) else {
            try? FileManager.default.removeItem(at: output)
            return false
        }
        log.notice("Saved a copy of the edited video: \(output.path)")
        Clipboard.copy(fileURL: output)
        Toast.show("Saved a copy and copied \(output.lastPathComponent)", duration: .seconds(3))
        return true
    }

    /// Copies keep the recording's format when AVFoundation can write it, and are MP4 otherwise.
    private static func copyExtension(of url: URL) -> String {
        url.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
    }

    /// The project as exported: with the sound left out if the options say so.
    private var exportProject: Project {
        var exported = project
        if options.muted {
            for index in exported.tracks.indices where exported.tracks[index].kind == .audio {
                exported.tracks[index].isMuted = true
            }
        }
        return exported
    }

    /// Writes a new file next to the original with the trim, cuts and export options, and copies it.
    func export() async {
        // Checked before picking a name, so two exports can't pick the same one.
        guard !isExporting else {
            return
        }
        let options = options, range = range, cuts = cuts, source = fileURL, composite = isComposite, edited = exportProject
        let output = FileNaming.uniqueURL(in: source.deletingLastPathComponent(), date: Date(), pathExtension: options.format.fileExtension, prefix: Preferences().filePrefix)
        var note = ""
        let progress = PercentProgress { percent in
            Task { @MainActor in
                Toast.progress("Exporting… \(percent)%")
            }
        }
        let exported = await exporting {
            if composite {
                switch options.format {
                case .mp4:
                    try await ProjectExporter.export(edited, to: output, as: .mp4)
                    log.notice("Exported composite MP4, muted \(options.muted, privacy: .public)")
                case .gif:
                    let built = try await CompositionBuilder.build(edited)
                    let result = try await GIFExporter.export(composition: built, to: output, fps: Double(options.gifFrameRate), maxWidth: options.gifMaxWidth, speed: options.speed, progress: progress.report)
                    note = result.truncated ? " (first \(Int(GIFExporter.maxDuration)) s only)" : ""
                    log.notice("Exported composite GIF: \(result.frameCount, privacy: .public) frames")
                }
                return
            }
            switch options.format {
            case .mp4:
                let passthrough = try await VideoTrimmer.trim(source, range: range, cuts: cuts, speed: options.speed, muted: options.muted, to: output, as: .mp4)
                log.notice("Exported MP4 at \(options.speed, privacy: .public)×, muted \(options.muted, privacy: .public), passthrough \(passthrough, privacy: .public)")
            case .gif:
                let result = try await GIFExporter.export(
                    videoURL: source, to: output, range: range, cuts: cuts, fps: Double(options.gifFrameRate), maxWidth: options.gifMaxWidth, speed: options.speed,
                    progress: progress.report
                )
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
        let options = options, range = range, cuts = cuts, source = fileURL, composite = isComposite, edited = exportProject
        // Wait for a drag or a run of clicks to settle before reading frames.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else {
            return
        }
        do {
            let size = switch options.format {
            case .mp4 where composite:
                ProjectExporter.estimatedSize(of: edited)
            case .gif where composite:
                try await GIFExporter.estimatedSize(of: CompositionBuilder.build(edited), fps: Double(options.gifFrameRate), maxWidth: options.gifMaxWidth, speed: options.speed)
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
        await exporting { [self] in
            if let folder {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            if isComposite {
                try await ProjectExporter.export(project, to: output, as: Self.copyExtension(of: fileURL) == "mov" ? .mov : .mp4)
                log.notice("Exported the edit with \(self.project.tracks.count, privacy: .public) tracks")
                return
            }
            let passthrough = try await VideoTrimmer.trim(fileURL, range: range, cuts: cuts, to: output)
            log.notice("Trimmed \(self.range.start, privacy: .public)–\(self.range.end, privacy: .public) s less \(self.cuts.cuts.count, privacy: .public) cuts, passthrough \(passthrough, privacy: .public)")
        }
    }

    /// Runs `work` with the player paused, one export at a time; false if it couldn't start, failed or was cancelled.
    private func exporting(_ work: @escaping () async throws -> Void) async -> Bool {
        guard exportTask == nil else {
            return false
        }
        player.pause()
        Toast.show("Exporting…", duration: nil)
        let task = Task {
            defer { exportTask = nil }
            do {
                try await work()
                return true
            } catch where Task.isCancelled {
                log.notice("Export cancelled")
                Toast.show("Export cancelled")
                return false
            } catch {
                log.error("Export failed: \(error.localizedDescription, privacy: .public)")
                Toast.error("Export failed: \(error.localizedDescription)")
                return false
            }
        }
        exportTask = task
        return await task.value
    }

    /// Stops the export in progress; false when there isn't one.
    @discardableResult
    func cancelExport() -> Bool {
        exportTask?.cancel()
        return exportTask != nil
    }

    /// Returns once the export in progress, if any, has finished or stopped.
    func exportEnded() async {
        _ = await exportTask?.value
    }
}

// MARK: Annotating

extension VideoEditorModel {
    var isAnnotating: Bool { annotationTool != nil }

    var selectedAnnotation: AnnotationClip? { selectedClipID.flatMap(project.annotationClip) }

    /// Canvas pixels per point of a new annotation's strokes and corners, so they look the same on a 4K recording as on a small one.
    var styleScale: CGFloat { max(1, project.canvasSize.width / 960) }
    var lineWidth: CGFloat { EditorStyle.widths[annotationStyle.widthIndex] * styleScale }
    var fontSize: CGFloat { lineWidth * 6 }
    var cornerRadius: CGFloat { Annotation.defaultCornerRadius * styleScale }

    /// Picks the tool that draws over the video, or nil to stop; the preview plays the composite while one is picked.
    func setAnnotationTool(_ tool: EditorTool?) {
        guard tool != annotationTool, tool != .crop, tool != .hand else {
            return
        }
        player.pause()
        annotationTool = tool
        if tool != nil, tool != .select {
            selectedClipID = selectedAnnotation == nil ? selectedClipID : nil
        }
        onLayoutChanged?()
        refreshPlayer()
    }

    var paletteColor: RGBA {
        get {
            editingText?.color ?? selectedAnnotation?.annotation.color ?? nextColor
        }
        set {
            if let text = editingText {
                // The field commits it; new text or a new note also sets the colour for the next one.
                editingText?.color = newValue
                if project.annotationClip(text.id) == nil {
                    if case .note = text.kind {
                        annotationStyle.noteColor = newValue
                    } else {
                        annotationStyle.color = newValue
                    }
                }
            } else if selectedAnnotation != nil {
                restyleSelection { $0.color = newValue }
            } else {
                nextColor = newValue
            }
        }
    }

    /// The colour for the tool's next annotation: notes and the highlighter keep their own.
    var nextColor: RGBA {
        get {
            switch annotationTool {
            case .note: annotationStyle.noteColor
            case .highlight: annotationStyle.highlightColor
            default: annotationStyle.color
            }
        }
        set {
            switch annotationTool {
            case .note: annotationStyle.noteColor = newValue
            case .highlight: annotationStyle.highlightColor = newValue
            default: annotationStyle.color = newValue
            }
        }
    }

    /// True when the palette offers a colour and width: the text being typed or the selected annotation takes them, or else the tool does.
    var showsStyle: Bool {
        editingText != nil || (selectedAnnotation?.annotation.isStyled ?? annotationTool?.isStyled ?? false)
    }

    /// True when the width sets a text size, so the palette offers sizes rather than line widths.
    var sizesText: Bool {
        (editingText ?? selectedAnnotation?.annotation)?.sizesText ?? annotationTool?.sizesText ?? false
    }

    var showsFill: Bool {
        selectedAnnotation?.annotation.supportsFill ?? (annotationTool == .shape)
    }

    /// The outline the palette shows: the selected shape's, else the next shape's. `nil` when neither is a shape.
    var paletteShape: BoxShape? {
        if let selected = selectedAnnotation?.annotation {
            guard case let .shape(shape, _) = selected.kind else {
                return nil
            }
            return shape
        }
        return annotationTool == .shape ? annotationStyle.shape : nil
    }

    func setShape(_ shape: BoxShape) {
        guard selectedAnnotation != nil else {
            annotationStyle.shape = shape
            return
        }
        restyleSelection {
            if case let .shape(_, rect) = $0.kind {
                $0.kind = .shape(shape, rect: rect)
            }
        }
    }

    /// How the palette shows a redaction hiding: the selected one's, else the next one's. `nil` when neither is one.
    var paletteRedaction: Redaction? {
        if let selected = selectedAnnotation?.annotation {
            return selected.redaction
        }
        return annotationTool == .redact ? annotationStyle.redaction : nil
    }

    func setRedaction(_ redaction: Redaction) {
        guard selectedAnnotation != nil else {
            annotationStyle.redaction = redaction
            return
        }
        restyleSelection { $0.setRedaction(redaction) }
    }

    /// How strongly the palette shows a redaction hiding: the selected one's, else the next one's.
    var paletteRedactionAmount: CGFloat {
        let length = max(project.canvasSize.width, project.canvasSize.height)
        return selectedAnnotation?.annotation.redactionAmount(imageLength: length) ?? annotationStyle.redactionAmount
    }

    /// Sets how strongly the selected redaction, or the next one, hides. Between `beginDrag` and `endDrag` the changes are one undo step.
    func setRedactionAmount(_ amount: CGFloat) {
        guard let clip = selectedAnnotation else {
            annotationStyle.redactionAmount = amount
            return
        }
        var restyled = clip.annotation
        restyled.setRedactionAmount(amount)
        commitAnnotation(restyled, id: clip.id)
    }

    /// The next spotlight's style: the chosen shape and edge, with the effect and strength the project's spotlights already share.
    var nextSpotlightStyle: SpotlightStyle {
        let shared = project.annotationClips.map(\.annotation).spotlightStyle ?? annotationStyle.spotlight
        let next = annotationStyle.spotlight
        return SpotlightStyle(shape: next.shape, effect: shared.effect, strength: shared.strength, softEdge: next.softEdge)
    }

    /// The spotlight style the palette shows: the selected spotlight's, else the next one's. `nil` when neither is one.
    var paletteSpotlight: SpotlightStyle? {
        if let selected = selectedAnnotation?.annotation {
            guard case let .spotlight(_, style) = selected.kind else {
                return nil
            }
            return style
        }
        return annotationTool == .spotlight ? nextSpotlightStyle : nil
    }

    func setSpotlightShape(_ shape: BoxShape) {
        guard selectedAnnotation != nil else {
            annotationStyle.spotlight.shape = shape
            return
        }
        restyleSelection { $0.restyleSpotlight { $0.shape = shape } }
    }

    /// Between `beginDrag` and `endDrag` the changes are one undo step.
    func setSpotlightSoftEdge(_ softEdge: Double) {
        guard var restyled = selectedAnnotation else {
            annotationStyle.spotlight.softEdge = softEdge
            return
        }
        restyled.annotation.restyleSpotlight { $0.softEdge = softEdge }
        commitAnnotation(restyled.annotation, id: restyled.id)
    }

    /// Sets the effect and strength of every spotlight in the project, since they share one dim, and of the next one.
    /// Between `beginDrag` and `endDrag` the changes are one undo step.
    func setSpotlightLook(effect: SpotlightStyle.Effect, strength: Double) {
        annotationStyle.spotlight.effect = effect
        annotationStyle.spotlight.strength = strength
        let changed = project.settingSpotlights(effect: effect, strength: strength)
        guard !isExporting, changed != project else {
            return
        }
        if dragOrigin == nil {
            undoStack.record(edit)
        }
        project = changed
    }

    /// The alignment the palette shows: the text being typed's, else the selected annotation's, else the next text's or note's.
    /// `nil` when none of them is text or a note.
    var paletteAlignment: TextAlign? {
        if let shown = editingText ?? selectedAnnotation?.annotation {
            return shown.alignsText ? shown.alignment : nil
        }
        return annotationTool == .text || annotationTool == .note ? annotationStyle.alignment : nil
    }

    func setAlignment(_ alignment: TextAlign) {
        if let text = editingText {
            // The field commits it; new text or a new note also sets the alignment for the next one.
            editingText?.alignment = alignment
            if project.annotationClip(text.id) == nil {
                annotationStyle.alignment = alignment
            }
        } else if selectedAnnotation != nil {
            restyleSelection { $0.alignment = alignment }
        } else {
            annotationStyle.alignment = alignment
        }
    }

    var paletteFill: RGBA? {
        get { selectedAnnotation?.annotation.fill ?? (selectedAnnotation == nil ? annotationStyle.fill : nil) }
        set {
            if selectedAnnotation != nil {
                restyleSelection { $0.fill = newValue }
            } else {
                annotationStyle.fill = newValue
            }
        }
    }

    var lineWidthIndex: Int {
        get {
            guard let selected = editingText ?? selectedAnnotation?.annotation else {
                return annotationStyle.widthIndex
            }
            let scale = max(1, project.canvasSize.width / 960)
            return EditorStyle.widths.indices.min { abs(EditorStyle.widths[$0] * scale - selected.lineWidth) < abs(EditorStyle.widths[$1] * scale - selected.lineWidth) } ?? annotationStyle.widthIndex
        }
        set {
            if let text = editingText {
                // Text resizes as it's typed; new text also sets the width for the next annotation.
                editingText?.setLineWidth(EditorStyle.widths[newValue] * max(1, project.canvasSize.width / 960))
                if project.annotationClip(text.id) == nil {
                    annotationStyle.widthIndex = newValue
                }
            } else if selectedAnnotation != nil {
                restyleSelection { $0.setLineWidth(EditorStyle.widths[newValue] * max(1, project.canvasSize.width / 960)) }
            } else {
                annotationStyle.widthIndex = newValue
            }
        }
    }

    func pickCustom(_ color: RGBA, forFill: Bool) {
        if forFill {
            paletteFill = color
        } else {
            paletteColor = color
        }
        let slot = customSlot(forFill: forFill)
        annotationStyle.customColors[slot] = color
        // Only the custom colour is remembered: the video editor's other choices last as long as its window.
        var style = Preferences().editorStyle
        style.customColors[slot] = color
        Preferences.remember(style)
    }

    /// The colour or fill palette's last custom colour.
    func lastCustom(forFill: Bool) -> RGBA? {
        annotationStyle.customColors[customSlot(forFill: forFill)]
    }

    private func customSlot(forFill: Bool) -> ColorSlot {
        ColorSlot(forFill: forFill, shown: editingText ?? selectedAnnotation?.annotation, tool: annotationTool)
    }

    /// Changes the selected annotation's style as one undo step, which a colour well's run of changes shares.
    private func restyleSelection(_ change: (inout Annotation) -> Void) {
        guard let clip = selectedAnnotation else {
            return
        }
        var restyled = clip.annotation
        change(&restyled)
        commitAnnotation(restyled, id: clip.id)
    }

    /// Shows the compositor `annotation` at the playhead, in place of the clip `id` when it has one, before it's committed.
    func previewAnnotation(_ annotation: Annotation?, replacing id: UUID? = nil) {
        guard let annotation else {
            liveState = ([], [])
            compositeLive?.clear()
            refreshFrame()
            return
        }
        let existing = id.flatMap(project.annotationClip)
        let clip = AnnotationClip(id: id ?? UUID(), annotation: annotation, start: existing?.start ?? playhead, duration: existing?.duration ?? AnnotationClip.defaultDuration)
        liveState = (id.map { [$0] } ?? [], [clip])
        compositeLive?.set(hidden: liveState.hidden, drawn: liveState.drawn)
        refreshFrame()
    }

    /// Stops drawing the annotation clip `id`, which a text field is editing in place, until it's committed.
    func hideAnnotation(_ id: UUID) {
        liveState = ([id], [])
        compositeLive?.set(hidden: liveState.hidden, drawn: liveState.drawn)
        refreshFrame()
    }

    /// Escape leaves the annotation tool, or deselects the annotation first; false when there's nothing to leave.
    func escapeAnnotating() -> Bool {
        if selectedClipID != nil {
            selectedClipID = nil
            return true
        }
        guard isAnnotating else {
            return false
        }
        setAnnotationTool(nil)
        return true
    }

    /// Pauses before an edit, and leaves the player showing the frame it's editing.
    func pauseForEditing() {
        player.pause()
    }

    /// Redraws the frame the paused player is showing, which a change to the live annotations doesn't do by itself.
    private func refreshFrame() {
        guard itemIsComposite, !isPlaying else {
            return
        }
        player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Puts `annotation` on the timeline at the playhead and selects it.
    func addAnnotation(_ annotation: Annotation) {
        guard !isExporting else {
            return
        }
        let (added, id) = project.adding(annotation: annotation, at: playhead)
        undoStack.record(edit)
        project = added
        selectedClipID = id
    }

    /// Replaces what the annotation clip `id` shows, as one undo step; between `beginDrag` and `endDrag`, `endDrag` records it.
    func commitAnnotation(_ annotation: Annotation, id: UUID) {
        guard !isExporting, let changed = project.setting(annotation: annotation, ofClip: id), changed != project else {
            return
        }
        if dragOrigin == nil {
            undoStack.record(edit)
        }
        project = changed
        // The compositor keeps drawing the live version until the rebuilt preview has it too.
        let clip = changed.annotationClip(id)
        liveState = ([id], clip.map { [$0] } ?? [])
        compositeLive?.set(hidden: liveState.hidden, drawn: liveState.drawn)
    }

    func setAnnotationText(_ id: UUID, to string: String, color: RGBA? = nil) {
        guard var annotation = project.annotationClip(id)?.annotation else {
            return
        }
        annotation.setText(string)
        if let color {
            annotation.color = color
        }
        commitAnnotation(annotation, id: id)
    }

    /// Puts an image from `url` on the video, centred and fitted inside half the canvas.
    func addImage(from url: URL) {
        guard let data = try? Data(contentsOf: url), let image = ImageCodec.image(from: data) else {
            Toast.error("Cannot open \(url.lastPathComponent): it isn't an image Shot can read")
            return
        }
        let canvas = project.canvasSize
        let scale = min(1, canvas.width / 2 / CGFloat(image.width), canvas.height / 2 / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let rect = CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
        addAnnotation(Annotation(kind: .image(AnnotationImage(image), rect: rect), color: annotationStyle.color, lineWidth: lineWidth))
    }
}

// MARK: Keyframes

extension VideoEditorModel {
    func toggleInspector() {
        showsInspector.toggle()
        UserDefaults.standard.set(showsInspector, forKey: Self.showsInspectorKey)
        onLayoutChanged?()
    }

    /// The selected clip's properties at the playhead, with its keyframes applied.
    var selectedValues: PropertyValues? {
        selectedClipID.flatMap { project.values(ofClip: $0, at: playhead) }
    }

    var selectedAnimation: ClipAnimation? {
        selectedClipID.flatMap(project.animation(ofClip:))
    }

    /// Sets the selected clip's properties at the playhead: a keyframed property gets a keyframe here, any other just changes.
    /// While dragging, call between `beginDrag` and `endDrag`; otherwise it's one undo step.
    func setValues(_ values: PropertyValues, of id: UUID? = nil) {
        guard !isExporting, let id = id ?? selectedClipID else {
            return
        }
        let before = dragOrigin
        guard let changed = (before ?? project).setting(values: values, ofClip: id, at: playhead), changed != project else {
            return
        }
        if before == nil {
            undoStack.record(edit)
        }
        project = changed
    }

    /// Adds a keyframe of `property` at the playhead holding its current value, or takes the one there away.
    func toggleKeyframe(_ property: AnimatedProperty) {
        guard !isExporting, let id = selectedClipID, let changed = project.togglingKeyframe(property, ofClip: id, at: playhead) else {
            return
        }
        undoStack.record(edit)
        project = changed
    }

    /// Keys everything the selected clip can animate at the playhead, or takes those keyframes away if any are there already.
    func toggleAllKeyframes() {
        guard !isExporting, let id = selectedClipID, let start = project.clipStart(id), let animation = project.animation(ofClip: id) else {
            return
        }
        let isSound = project.clip(id).map { clip in project.tracks.contains { $0.kind == .audio && $0.clips.contains { $0.id == clip.id } } } ?? false
        let properties: [AnimatedProperty] = isSound ? [.volume] : [.position, .scale, .rotation, .opacity]
        let relative = max(0, playhead - start)
        let anyHere = properties.contains { animation.hasKeyframe($0, at: relative) }
        var changed = project
        for property in properties where anyHere == animation.hasKeyframe(property, at: relative) {
            changed = changed.togglingKeyframe(property, ofClip: id, at: playhead) ?? changed
        }
        guard changed != project else {
            return
        }
        undoStack.record(edit)
        project = changed
    }

    func applyPreset(_ preset: AnimationPreset) {
        guard !isExporting, let id = selectedClipID, let changed = project.applying(preset, toClip: id), changed != project else {
            return
        }
        undoStack.record(edit)
        project = changed
    }

    /// Selects a keyframe, `time` seconds into the selected clip, and puts the playhead on it.
    func selectKeyframe(_ time: Double?) {
        selectedKeyframe = time
        if let time, let id = selectedClipID, let start = project.clipStart(id) {
            seekTimeline(to: min(start + time, project.duration))
        }
    }

    func setKeyframeEasing(_ easing: Easing) {
        guard !isExporting, let id = selectedClipID, let time = selectedKeyframe, let changed = project.settingEasing(easing, ofClip: id, at: time), changed != project else {
            return
        }
        undoStack.record(edit)
        project = changed
    }

    /// Takes away the selected keyframe, with those of other properties at the same moment; false when none is selected.
    func deleteSelectedKeyframe() -> Bool {
        guard let id = selectedClipID, let time = selectedKeyframe, !isExporting else {
            return false
        }
        selectedKeyframe = nil
        if let changed = project.removingKeyframes(ofClip: id, at: time) {
            undoStack.record(edit)
            project = changed
        }
        return true
    }

    func clearKeyframes() {
        guard !isExporting, let id = selectedClipID, let animation = project.animation(ofClip: id), !animation.isEmpty else {
            return
        }
        var changed = project
        for time in animation.times {
            changed = changed.removingKeyframes(ofClip: id, at: time) ?? changed
        }
        undoStack.record(edit)
        selectedKeyframe = nil
        project = changed
    }

    /// Drags the keyframes at `time` to timeline `target`; call between `beginDrag` and `endDrag`.
    func moveKeyframe(_ id: UUID, from time: Double, toTimeline target: Double) {
        guard let origin = dragOrigin, let start = origin.clipStart(id), let moved = origin.movingKeyframes(ofClip: id, from: time, to: target - start) else {
            return
        }
        project = moved
        selectedKeyframe = min(max(target - start, 0), origin.clip(id)?.length ?? origin.annotationClip(id)?.duration ?? 0)
    }
}

/// What fetches a video's thumbnails, kept from one load to the next along with the frames it has fetched.
@MainActor
private final class ThumbnailSource {
    let generator: AVAssetImageGenerator
    var cache = ThumbnailCache<CGImage>()

    init(url: URL, maximumSize: CGSize) {
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
    }
}
