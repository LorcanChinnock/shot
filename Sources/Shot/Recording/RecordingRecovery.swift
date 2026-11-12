import AppKit
import AVFoundation
import os
import ShotCore
import SwiftUI

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

    /// Looks for the segments a recording left in the temporary folder when it never finished, a crash say, and asks
    /// what to do with them. Call at launch, before anything records. Files that are empty or unreadable are deleted
    /// first; if any part still plays, the recovery dialog shows its length and offers to recover or discard it. Files
    /// written in the last ten minutes are left alone, in case another copy of Shot is recording into the same folder.
    nonisolated static func recoverLeftoverSegments() async {
        let folder = segmentsFolder
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        let files = found.map { SegmentRecovery.File(name: $0.lastPathComponent, modified: (try? $0.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast) }
        let plan = SegmentRecovery.plan(files)
        removeSegmentFiles(plan.orphans)
        var playable: [SegmentRecovery.Segment] = []
        var durations: [TimeInterval] = []
        for segment in plan.segments {
            if let duration = await playableDuration(folder.appendingPathComponent(segment.video)) {
                playable.append(segment)
                durations.append(duration)
            } else {
                removeSegmentFiles(segment.files)
            }
        }
        log.notice("Leftover segments: \(playable.count) to offer, \(plan.segments.count - playable.count + plan.orphans.count) swept")
        guard !playable.isEmpty else {
            return
        }
        let leftover = SegmentRecovery.Leftover(segments: playable, durations: durations)
        await MainActor.run { RecordingRecoveryDialog.show(leftover) }
    }

    /// The length of the segment at `url` in seconds, or nil when it can't be played.
    private nonisolated static func playableDuration(_ url: URL) async -> TimeInterval? {
        guard await isPlayable(url) else {
            return nil
        }
        return try? await AVURLAsset(url: url).load(.duration).seconds
    }

    private nonisolated static func removeSegmentFiles(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: segmentsFolder.appendingPathComponent(name))
        }
    }

    /// The recovery dialog's Recover: joins `leftover`'s parts into "… (recovered).mp4" in the save folder, or moves them
    /// there as separate parts when they can't be joined, with a toast to show the file.
    nonisolated static func recover(_ leftover: SegmentRecovery.Leftover) async {
        let folder = segmentsFolder
        guard let first = leftover.segments.first, let saveFolder = try? recoveryFolder() else {
            await MainActor.run { Toast.error("Couldn't recover the recording. Shot will ask again the next time it opens.") }
            return
        }
        await MainActor.run { Toast.show("Recovering the recording…", duration: nil) }
        let videos = leftover.segments.map { folder.appendingPathComponent($0.video) }
        let audio = SegmentRecovery.audio(of: leftover.segments)?.map {
            VideoConcatenator.SegmentAudio(system: folder.appendingPathComponent($0.system), microphone: folder.appendingPathComponent($0.microphone))
        }
        let output = FileNaming.recoveredURL(in: saveFolder, date: first.modified, prefix: Preferences().filePrefix)
        // The audio files only let the microphone be muted, so if they're what stops a join, the segments' own audio will do.
        for attempt in audio.map({ [$0, []] }) ?? [[]] {
            do {
                try await VideoConcatenator.concatenate(videos, audio: attempt, to: output)
                removeSegmentFiles(leftover.files)
                log.notice("Recovered \(leftover.parts) segments to \(output.path, privacy: .public)")
                await MainActor.run { Toast.show("Recovered an interrupted recording", duration: .seconds(8), reveal: output) }
                return
            } catch {
                log.error("Joining leftover segments failed: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: output)
            }
        }
        let remaining = videos.filter { FileManager.default.fileExists(atPath: $0.path) }
        if let kept = await keepAsIs(remaining, date: first.modified) {
            // Only the audio of parts that moved; a part whose move failed keeps its files, for the next launch to offer.
            let moved = leftover.segments.filter { !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.video).path) }
            removeSegmentFiles(moved.flatMap(\.files))
            await MainActor.run { Toast.show("Saved the parts of an interrupted recording", duration: .seconds(8), reveal: kept[0]) }
        } else {
            await MainActor.run { Toast.error("Couldn't recover the recording. Shot will ask again the next time it opens.") }
        }
    }

    /// The recovery dialog's Discard recording: deletes every file `leftover`'s parts were written to.
    nonisolated static func discard(_ leftover: SegmentRecovery.Leftover) {
        removeSegmentFiles(leftover.files)
        log.notice("Leftover recording discarded")
    }

    /// Where `leftover`'s parts are, for the dialog's Show Parts.
    nonisolated static func partURLs(_ leftover: SegmentRecovery.Leftover) -> [URL] {
        leftover.segments.map { segmentsFolder.appendingPathComponent($0.video) }
    }
}

/// The centred dialog that asks what to do with a recording that never finished (Capture › Permission card… ›
/// Recovering a recording). It says how long the recording is and how many parts it was saved in, and offers Show Parts,
/// Recover as the main button, and Discard recording, which the discard toast can undo. It takes the keyboard: Return
/// recovers, and Esc puts the choice off until Shot next opens.
final class RecordingRecoveryDialog: FloatingPanelWindow {
    struct Actions {
        let showParts: @MainActor () -> Void
        let recover: @MainActor () -> Void
        let discard: @MainActor () -> Void
    }

    private static var shown: RecordingRecoveryDialog?

    private let leftover: SegmentRecovery.Leftover

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    static func show(_ leftover: SegmentRecovery.Leftover) {
        shown?.dismiss()
        let dialog = RecordingRecoveryDialog(leftover: leftover)
        shown = dialog
        dialog.present()
    }

    private init(leftover: SegmentRecovery.Leftover) {
        self.leftover = leftover
        let size = NSSize(width: RecordingRecoveryView.width(Preferences().textSize), height: 240)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless])
        // Shot is a menu bar app, so macOS may refuse to bring it forward at launch; the level keeps the dialog in view anyway.
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        title = RecordingRecoveryView.title
        setAccessibilitySubrole(.dialog)
        let actions = Actions(
            showParts: { NSWorkspace.shared.activateFileViewerSelecting(Recorder.partURLs(leftover)) },
            recover: { [weak self] in
                self?.dismiss()
                Task.detached { await Recorder.recover(leftover) }
            },
            discard: { [weak self] in
                self?.dismiss()
                let pending = PendingAction(
                    commit: { Recorder.discard(leftover) },
                    undo: { RecordingRecoveryDialog.show(leftover) }
                )
                Toast.show("Recording discarded", duration: .seconds(5), undoable: pending)
            }
        )
        contentView = NSView(hosting: RecordingRecoveryView(leftover: leftover, actions: actions) { [weak self] size in
            self?.fit(size)
        })
        contentView?.layoutSubtreeIfNeeded()
    }

    /// Esc closes the dialog without deciding. The parts stay, so Shot asks again the next time it opens.
    override func cancelOperation(_ sender: Any?) {
        log.notice("Leftover recording put off until the next launch")
        dismiss()
    }

    private func dismiss() {
        orderOut(nil)
        if Self.shown === self {
            Self.shown = nil
        }
    }

    /// Centres the dialog on the screen with the pointer and brings it forward. It fades in as it rises a few points, or
    /// only fades with Reduce Motion.
    private func present() {
        let frame = centred(frame.size)
        let reduced = Motion.reduced
        alphaValue = 0
        setFrame(reduced ? frame : frame.offsetBy(dx: 0, dy: -8), display: true)
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? Moment.reducedFade : Moment.panelArrive.duration
            context.timingFunction = reduced ? CAMediaTimingFunction(name: .easeOut) : Motion.arriveCurve
            animator().alphaValue = 1
            if !reduced {
                animator().setFrame(frame, display: true)
            }
        }
        let text = "\(RecordingRecoveryView.title). \(RecordingRecoveryView.detail(leftover))"
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    private func centred(_ size: NSSize) -> NSRect {
        let screen = (NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(x: (screen.midX - size.width / 2).rounded(), y: (screen.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// Takes the height the text needs at the chosen text size, keeping the dialog's middle where it was.
    private func fit(_ size: CGSize) {
        let wanted = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted != frame.size, wanted.width > 0, wanted.height > 0 else {
            return
        }
        let resting = isVisible ? frame : centred(frame.size)
        setFrame(NSRect(x: (resting.midX - wanted.width / 2).rounded(), y: (resting.midY - wanted.height / 2).rounded(), width: wanted.width, height: wanted.height), display: true)
    }
}

private struct RecordingRecoveryView: View {
    let leftover: SegmentRecovery.Leftover
    let actions: RecordingRecoveryDialog.Actions
    let onSize: (CGSize) -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.textSize) private var textSize

    static let padding: CGFloat = 20
    static let spacing: CGFloat = 10
    static let tile: CGFloat = 44
    static let buttonGap: CGFloat = 8

    static var title: String { String(localized: "Recover your last recording?") }

    static func detail(_ leftover: SegmentRecovery.Leftover) -> String {
        let length = leftover.length
        if leftover.parts == 1 {
            return String(localized: "Shot stopped while recording. \(length) was saved, and Shot can put it in your save folder now.")
        }
        return String(localized: "Shot stopped while recording. \(length) was saved in \(leftover.parts) parts, and Shot can join them now.")
    }

    /// 320 pt on the board, wider with Settings › Text size so the text wraps as it does there.
    static func width(_ textSize: TextSize) -> CGFloat {
        (320 * CGFloat(textSize.scale)).rounded()
    }

    private var increased: Bool { contrast == .increased }

    var body: some View {
        let scale = CGFloat(textSize.scale)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .circular)
        VStack(spacing: Self.spacing) {
            Image(systemName: "record.circle")
                .font(.scaled(22, weight: .medium))
                .foregroundStyle(Theme.SidebarTint.recording.icon)
                .frame(width: (Self.tile * scale).rounded(), height: (Self.tile * scale).rounded())
                .background(Theme.SidebarTint.recording.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular))
                .accessibilityHidden(true)
            Text(Self.title)
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(Self.detail(leftover))
                .font(.scaled(12.5))
                .lineSpacing(3)
                .foregroundStyle(increased ? Theme.ink : Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ButtonRow(shares: [1, 1], gap: Self.buttonGap) {
                Button { actions.showParts() } label: {
                    (leftover.parts == 1 ? Text("Show File") : Text("Show Parts")).frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemeButtonStyle())
                .help(String(localized: "Show what was recorded in Finder"))
                Button { actions.recover() } label: {
                    Text("Recover").frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemeButtonStyle(.main))
                .keyboardShortcut(.defaultAction)
                .help(String(localized: "Save the recording to your save folder"))
            }
            .padding(.top, 6)
            Button { actions.discard() } label: {
                Text("Discard recording")
            }
            .buttonStyle(ThemeButtonStyle(.plain, destructive: true))
            .help(String(localized: "Delete what was recorded. Undo brings it back for 5 seconds."))
        }
        .padding(Self.padding)
        .frame(width: Self.width(textSize))
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.group, in: shape)
        .inkBorder(shape, width: increased ? 1 : 0.5, color: edge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.title)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }

    /// The Float edge: black at 20% in light and white at 14% in dark, and 60% ink with Increase Contrast.
    private var edge: Color {
        if increased {
            return Theme.ink.opacity(0.6)
        }
        return colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.2)
    }
}
