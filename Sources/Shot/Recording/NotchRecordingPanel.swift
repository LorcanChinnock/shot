import AppKit
import Observation
import SwiftUI

/// A black pill growing out of the notch with the recording dot and time; hovering it shows the recording controls.
/// Like the floating controls, it is excluded from the capture, so it never appears in the video.
final class NotchRecordingPanel: NSPanel {
    /// Room either side of the notch for the dot and the time.
    private static let wing: CGFloat = 72

    private let collapsedFrame: CGRect
    private let expandedFrame: CGRect
    private let hover = NotchHover()

    /// `notch` is the AppKit global frame of the camera housing.
    @MainActor
    init(notch: CGRect, model: RecordingSessionModel, actions: RecordingControlPanel.Actions) {
        collapsedFrame = notch.insetBy(dx: -Self.wing, dy: 0)
        // The floating panel's size fits the controls.
        let controls = RecordingControlPanel.size(microphone: model.microphoneOn)
        let size = CGSize(width: max(collapsedFrame.width, controls.width), height: notch.height + controls.height)
        expandedFrame = CGRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height, width: size.width, height: size.height)
        super.init(contentRect: collapsedFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the menu bar and its status items, which the pill partly covers.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NotchRecordingView(model: model, actions: actions, hover: hover, notch: notch.size, statusWidth: collapsedFrame.width) { [weak self] hovering in
            self?.setExpanded(hovering)
        }
        contentView = NSView(hosting: view)
    }

    private func setExpanded(_ expanded: Bool) {
        hover.isExpanded = expanded
        setFrame(expanded ? expandedFrame : collapsedFrame, display: true)
    }
}

@MainActor
@Observable
private final class NotchHover {
    var isExpanded = false
}

private struct NotchRecordingView: View {
    let model: RecordingSessionModel
    let actions: RecordingControlPanel.Actions
    let hover: NotchHover
    let notch: CGSize
    let statusWidth: CGFloat
    let onHover: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RecordingDot(isPaused: model.isPaused)
                    .frame(maxWidth: .infinity)
                Color.clear
                    .frame(width: notch.width)
                ElapsedTime(model: model, color: .white)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: statusWidth, height: notch.height)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(model.isPaused ? "Paused" : "Recording"))
            if hover.isExpanded {
                RecordingControls(model: model, actions: actions)
                    .padding(.horizontal, 14)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: hover.isExpanded ? 18 : notch.height / 2, bottomTrailingRadius: hover.isExpanded ? 18 : notch.height / 2))
        .onHover(perform: onHover)
        .environment(\.colorScheme, .light)
    }
}
