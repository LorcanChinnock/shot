import AppKit
import ShotCore
import SwiftUI

/// Floating recording controls, a dark pill. Shot's windows are excluded from the capture, so they never appear in the video.
final class RecordingControlPanel: FloatingPanelWindow {
    struct Actions {
        let togglePause: @MainActor () -> Void
        let toggleMute: @MainActor () -> Void
        let toggleCamera: @MainActor () -> Void
        let cycleCameraSize: @MainActor () -> Void
        let stop: @MainActor (_ discard: Bool) -> Void
    }

    /// Wider when the microphone controls show.
    static func size(microphone: Bool) -> NSSize {
        NSSize(width: microphone ? 552 : 452, height: 54)
    }

    @MainActor
    init(region: CGRect, screen: NSScreen, model: RecordingSessionModel, actions: Actions) {
        let size = Self.size(microphone: model.microphoneOn)
        let origin = ControlPlacement.origin(for: size, region: region, visible: screen.visibleFrame)
        super.init(contentRect: NSRect(origin: origin, size: size))
        level = .statusBar
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSView(hosting: RecordingControlView(model: model, actions: actions))
    }
}

private struct RecordingControlView: View {
    let model: RecordingSessionModel
    let actions: RecordingControlPanel.Actions

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                RecordingDot(isPaused: model.isPaused)
                ElapsedTime(model: model, color: .white)
                    .frame(width: 50, alignment: .leading)
            }
            .brutalTip(model.isPaused ? "Paused" : "Recording")
            RecordingControls(model: model, actions: actions)
        }
        .padding(.leading, 20)
        .padding(.trailing, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .floatingPanel(Capsule())
    }
}

/// Pulses while recording; yellow and still while paused.
struct RecordingDot: View {
    let isPaused: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(isPaused ? Brutal.yellow : Brutal.red)
            .inkBorder(Circle(), width: 2)
            .frame(width: 14, height: 14)
            .opacity(pulse && !isPaused ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
            .onAppear { pulse = true }
    }
}

struct ElapsedTime: View {
    let model: RecordingSessionModel
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Text(format(model.elapsed(at: context.date)))
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Pause, microphone, camera, discard and stop.
struct RecordingControls: View {
    let model: RecordingSessionModel
    let actions: RecordingControlPanel.Actions

    var body: some View {
        HStack(spacing: 8) {
            Button {
                actions.togglePause()
            } label: {
                Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 70)
                    .fixedSize()
            }
            .buttonStyle(BrutalButtonStyle(model.isPaused ? .main : .toolbar, floating: true))
            .brutalTip(model.isPaused ? "Resume recording" : "Pause recording")

            if model.microphoneOn {
                HStack(spacing: 8) {
                    IconButton(symbol: model.microphoneMuted ? "mic.slash.fill" : "mic.fill", isOn: false, help: model.microphoneMuted ? "Unmute microphone" : "Mute microphone") {
                        actions.toggleMute()
                    }
                    LevelMeter(meter: model.meter, muted: model.microphoneMuted)
                }
            }

            if model.cameraAvailable {
                IconButton(symbol: model.cameraOn ? "video.fill" : "video.slash.fill", isOn: model.cameraOn, help: model.cameraOn ? "Hide camera bubble" : "Show camera bubble") {
                    actions.toggleCamera()
                }
                IconButton(symbol: "circle.circle", isOn: false, help: "Change camera bubble size") {
                    actions.cycleCameraSize()
                }
                .disabled(!model.cameraOn)
            }

            Spacer(minLength: 0)
            IconButton(symbol: "trash.fill", isOn: false, help: "Discard recording") {
                actions.stop(true)
            }
            Button {
                actions.stop(false)
            } label: {
                Label("Stop", systemImage: "stop.fill").labelStyle(.titleAndIcon).fixedSize()
            }
            .buttonStyle(BrutalButtonStyle(model.isPaused ? .secondary : .main, destructive: !model.isPaused, floating: true))
            .brutalTip("Stop and save")
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let isOn: Bool
    let help: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, isOn: isOn, floating: true))
        .brutalTip(help)
        .accessibilityLabel(Text(help))
    }
}
