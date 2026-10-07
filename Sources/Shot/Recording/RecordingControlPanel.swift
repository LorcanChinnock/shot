import AppKit
import ShotCore
import SwiftUI

/// Floating recording controls. Shot's windows are excluded from the capture, so they never appear in the video.
final class RecordingControlPanel: NSPanel {
    struct Actions {
        let togglePause: @MainActor () -> Void
        let toggleMute: @MainActor () -> Void
        let toggleCamera: @MainActor () -> Void
        let cycleCameraSize: @MainActor () -> Void
        let stop: @MainActor (_ discard: Bool) -> Void
    }

    /// Wider when the microphone controls show.
    private static func size(microphone: Bool) -> NSSize {
        NSSize(width: microphone ? 556 : 456, height: 62)
    }

    @MainActor
    init(region: CGRect, screen: NSScreen, model: RecordingSessionModel, actions: Actions) {
        let size = Self.size(microphone: model.microphoneOn)
        let origin = ControlPlacement.origin(for: size, region: region, visible: screen.visibleFrame)
        super.init(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
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
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isPaused ? Brutal.yellow : Brutal.red)
                    .inkBorder(Circle(), width: 2)
                    .frame(width: 14, height: 14)
                    .opacity(pulse && !model.isPaused ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                    .onAppear { pulse = true }
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(format(model.elapsed(at: context.date)))
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Brutal.ink)
                        .frame(width: 50, alignment: .leading)
                }
            }
            .brutalTip(model.isPaused ? "Paused" : "Recording")

            Button {
                actions.togglePause()
            } label: {
                Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 70)
                    .fixedSize()
            }
            .buttonStyle(BrutalButtonStyle(color: model.isPaused ? Brutal.yellow : .white, compact: true))
            .brutalTip(model.isPaused ? "Resume recording" : "Pause recording")

            if model.microphoneOn {
                HStack(spacing: 8) {
                    IconButton(symbol: model.microphoneMuted ? "mic.slash.fill" : "mic.fill", color: model.microphoneMuted ? Brutal.yellow : Brutal.mint, help: model.microphoneMuted ? "Unmute microphone" : "Mute microphone") {
                        actions.toggleMute()
                    }
                    LevelMeter(meter: model.meter, muted: model.microphoneMuted)
                }
            }

            IconButton(symbol: model.cameraOn ? "video.fill" : "video.slash.fill", color: model.cameraOn ? Brutal.mint : .white, help: model.cameraOn ? "Hide camera" : "Show camera") {
                actions.toggleCamera()
            }
            IconButton(symbol: "circle.circle", color: .white, help: "Camera bubble size") {
                actions.cycleCameraSize()
            }
            .disabled(!model.cameraOn)
            .opacity(model.cameraOn ? 1 : 0.35)

            Spacer(minLength: 0)
            IconButton(symbol: "trash.fill", color: .white, help: "Discard recording") {
                actions.stop(true)
            }
            Button {
                actions.stop(false)
            } label: {
                Label("Stop", systemImage: "stop.fill").labelStyle(.titleAndIcon).fixedSize()
            }
            .buttonStyle(BrutalButtonStyle(color: Brutal.red, compact: true))
            .brutalTip("Stop and save")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .brutalSurface(Color.white.opacity(0.72), glass: true, radius: 14, shadow: 4)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .environment(\.colorScheme, .light)
    }

    private func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct IconButton: View {
    let symbol: String
    let color: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(BrutalButtonStyle(color: color, compact: true))
        .brutalTip(help)
        .accessibilityLabel(Text(help))
    }
}
