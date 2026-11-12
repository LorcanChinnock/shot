import AppKit
import ShotCore
import SwiftUI

/// The recording controls (Record › While recording): a dark bar under the recorded area with the breathing red dot and
/// the timer, the microphone and its level, the camera bubble, Pause, Discard, and Stop as the one ink button. While paused,
/// Resume takes Pause's place as the ink button and Stop turns secondary. Shot's windows are left out of the capture, so
/// the bar never appears in the video.
final class RecordingControlPanel: FloatingPanelWindow {
    struct Actions {
        let togglePause: @MainActor () -> Void
        let toggleMute: @MainActor () -> Void
        let toggleCamera: @MainActor () -> Void
        let stop: @MainActor (_ discard: Bool) -> Void
    }

    /// From the recorded area's bottom edge to the bar, clear of the recording border's glow.
    static let gap: CGFloat = 22
    private let region: CGRect
    private let visibleFrame: CGRect
    private var placed = false

    @MainActor
    init(region: CGRect, screen: NSScreen, model: RecordingSessionModel, actions: Actions) {
        self.region = region
        visibleFrame = screen.visibleFrame
        super.init(contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: 48)))
        level = .statusBar
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let content = NSView(hosting: RecordingControlView(model: model, actions: actions) { [weak self] size in
            self?.fit(size)
        })
        contentView = content
        content.layoutSubtreeIfNeeded()
        fit(content.fittingSize)
    }

    /// The bar grows to fit its buttons at the chosen text size. It starts centred under the area; after that it keeps
    /// its middle and top edge as it changes size, so a bar you've dragged aside stays where you put it.
    private func fit(_ size: CGSize) {
        let wanted = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted.width > 0, wanted.height > 0, wanted != frame.size || !placed else {
            return
        }
        var origin: CGPoint
        if placed {
            origin = CGPoint(x: frame.midX - wanted.width / 2, y: frame.maxY - wanted.height)
            origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - wanted.width - 8)
        } else {
            origin = ControlPlacement.origin(for: wanted, region: region, visible: visibleFrame, gap: Self.gap)
            placed = true
        }
        setFrame(NSRect(origin: origin, size: wanted), display: true)
    }
}

private struct RecordingControlView: View {
    let model: RecordingSessionModel
    let actions: RecordingControlPanel.Actions
    let onSize: (CGSize) -> Void
    @Environment(\.textSize) private var textSize

    /// Buttons are 36 pt tall on the board: a floating toolbar button's 5 pt padding either side of this.
    static let toolbarContent: CGFloat = 26
    /// Stop and Resume at the same height, inside the main button's 8 pt padding.
    static let buttonContent: CGFloat = 20

    var body: some View {
        HStack(spacing: 4) {
            RecordingStatus(model: model)
            FloatingDivider()
            if model.microphoneOn {
                microphone
            }
            if model.cameraAvailable {
                camera
            }
            if model.isPaused {
                resume
            } else {
                pause
            }
            discard
            stop.padding(.leading, 4)
        }
        .padding(6)
        .fixedSize()
        .floatingPanel(RoundedRectangle(cornerRadius: 16, style: .circular))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isPaused ? Text("Recording paused") : Text("Recording"))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }

    private var scale: CGFloat { CGFloat(textSize.scale) }

    private var microphone: some View {
        let muted = model.microphoneMuted
        return Button(action: actions.toggleMute) {
            HStack(spacing: 6) {
                Image(systemName: muted ? "mic.slash" : "mic")
                    .font(.scaled(14, weight: .semibold))
                    .frame(width: (16 * scale).rounded())
                MicLevelColumns(meter: model.meter, active: !muted && !model.isPaused)
            }
            .foregroundStyle(muted ? ContrastAware(standard: .white.opacity(0.7), increased: .white.opacity(0.9)) : ContrastAware(standard: .white.opacity(0.9), increased: .white))
            .frame(minHeight: Self.toolbarContent)
            .padding(.horizontal, 3)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, floating: true))
        .brutalTip(microphoneTip)
        .accessibilityLabel(Text("Microphone"))
        .accessibilityValue(muted ? Text("Muted") : Text("On"))
        .accessibilityAddTraits(.isToggle)
    }

    private var camera: some View {
        let on = model.cameraOn
        return Button(action: actions.toggleCamera) {
            Image(systemName: on ? "video" : "video.slash")
                .font(.scaled(14, weight: .semibold))
                .frame(minWidth: Self.toolbarContent, minHeight: Self.toolbarContent)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, isOn: on, floating: true))
        .brutalTip(cameraTip, detail: "Double-click the bubble to change its size.")
        .accessibilityLabel(Text("Camera bubble"))
        .accessibilityValue(on ? Text("On") : Text("Off"))
        .accessibilityAddTraits(.isToggle)
    }

    private var pause: some View {
        Button(action: actions.togglePause) {
            Image(systemName: "pause.fill")
                .font(.scaled(13, weight: .semibold))
                .frame(minWidth: Self.toolbarContent, minHeight: Self.toolbarContent)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, floating: true))
        .brutalTip("Pause recording")
        .accessibilityLabel(Text("Pause"))
    }

    private var resume: some View {
        Button(action: actions.togglePause) {
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                    .font(.scaled(10, weight: .bold))
                    .accessibilityHidden(true)
                Text("Resume")
            }
            .frame(minHeight: Self.buttonContent)
        }
        .buttonStyle(BrutalButtonStyle(.main, floating: true))
        .brutalTip("Resume recording")
    }

    private var discard: some View {
        Button {
            actions.stop(true)
        } label: {
            Image(systemName: "trash")
                .font(.scaled(14, weight: .semibold))
                .frame(minWidth: Self.toolbarContent, minHeight: Self.toolbarContent)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, floating: true))
        .brutalTip("Discard recording")
        .accessibilityLabel(Text("Discard"))
    }

    private var stop: some View {
        let paused = model.isPaused
        return Button {
            actions.stop(false)
        } label: {
            HStack(spacing: 7) {
                if !paused {
                    let side = (10 * scale).rounded()
                    RoundedRectangle(cornerRadius: 2.5 * scale, style: .circular)
                        .fill(Color.white)
                        .frame(width: side, height: side)
                        .accessibilityHidden(true)
                }
                Text("Stop")
            }
            .frame(minHeight: Self.buttonContent)
        }
        .buttonStyle(BrutalButtonStyle(paused ? .secondary : .main, destructive: !paused, floating: true))
        .brutalTip("Stop and save")
    }

    private var microphoneTip: LocalizedStringResource {
        if model.microphoneMuted {
            return "Unmute the microphone"
        }
        return "Mute the microphone"
    }

    private var cameraTip: LocalizedStringResource {
        if model.cameraOn {
            return "Hide the camera bubble"
        }
        return "Show your camera in a bubble"
    }
}

/// The dot and the timer. Recording, the red dot breathes once every 1.6 s (a steady dot under Reduce Motion). Paused,
/// two amber marks take its place and the timer dims. VoiceOver reads it as one element: the state, then the time.
private struct RecordingStatus: View {
    let model: RecordingSessionModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let label = RecordingClock.label(model.seconds)
        HStack(spacing: 9) {
            if model.isPaused {
                PausedMarks()
            } else {
                BreathingDot()
            }
            // Tabular figures and the hidden zeroes hold the width, so the timer never jitters or nudges the bar.
            ZStack(alignment: .leading) {
                Text(verbatim: RecordingClock.placeholder(label)).hidden()
                Text(verbatim: label)
            }
            .font(.scaled(15, weight: .bold, design: .monospaced, tabular: true))
            .foregroundStyle(timerColor)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isPaused ? Text("Paused") : Text("Recording"))
        .accessibilityValue(Text(Duration.seconds(model.seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))))
    }

    /// White while recording; 70% while paused, as on the board (90% with Increase Contrast).
    private var timerColor: Color {
        guard model.isPaused else {
            return .white
        }
        return .white.opacity(contrast == .increased ? 0.9 : 0.7)
    }
}

/// Record red with a halo that breathes out of it over `Moment.recordingPulse`. Reduce Motion holds the board's steady
/// 4 pt halo instead. The frame loop runs at 30 fps, only while the dot shows.
private struct BreathingDot: View {
    @Environment(\.textSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// Record red as it reads on a dark panel, in both appearances.
    static let red = Color(hex: 0xFF453A)

    var body: some View {
        let side = (10 * CGFloat(textSize.scale)).rounded()
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let halo = halo(at: context.date)
            Circle()
                .fill(Self.red)
                .frame(width: side, height: side)
                .background {
                    Circle()
                        .fill(Self.red.opacity(halo.opacity))
                        .padding(-halo.spread)
                }
        }
        .accessibilityHidden(true)
    }

    private func halo(at date: Date) -> (spread: CGFloat, opacity: Double) {
        let scale = CGFloat(textSize.scale)
        guard !reduceMotion else {
            return (4 * scale, 0.25)
        }
        let breath = Moment.pulse(date.timeIntervalSince(start) / Moment.recordingPulse.duration)
        return (6 * scale * breath.spread, breath.opacity)
    }
}

/// Two amber bars, the board's paused mark. Amber reads as a hold without taking record red.
private struct PausedMarks: View {
    @Environment(\.textSize) private var textSize

    var body: some View {
        let scale = CGFloat(textSize.scale)
        HStack(spacing: (2 * scale).rounded()) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1, style: .circular)
                    .fill(MicLevelBars.loud)
                    .frame(width: (3 * scale).rounded(), height: (10 * scale).rounded())
            }
        }
        .frame(width: (10 * scale).rounded())
        .accessibilityHidden(true)
    }
}
