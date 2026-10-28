import AppKit
import Carbon.HIToolbox
import os
import ScreenCaptureKit
import ShotCore
import SwiftUI

private let log = Logger.shot("scroll-capture")

/// What the panel shows. Drives the status line and the colour of the outline around the area.
enum ScrollCaptureStatus: Equatable {
    case ready
    case stitching
    case tooFar
    case moving
    /// Blank or repeating content, where the shift can't be told.
    case featureless
    case limit
}

@MainActor
@Observable
final class ScrollCaptureModel {
    var status = ScrollCaptureStatus.ready
    var size = CGSize.zero
    var preview: CGImage?

    var message: LocalizedStringResource? {
        switch status {
        case .ready:
            "Scroll the content in any direction."
        case .stitching:
            nil
        case .tooFar:
            "Scrolled too far at once. Scroll back a little and carry on."
        case .moving:
            "Something in the area keeps changing, so Shot can't line frames up. Pause the video or scroll past it."
        case .featureless:
            "There isn't enough in the area to line frames up. Include some text or an image, or drag out another area."
        case .limit:
            "That's as big as Shot can stitch (30,000 px along a side). Press Return to save."
        }
    }

    var isWarning: Bool { status == .tooFar || status == .moving || status == .featureless }
}

/// Drives one scrolling capture: streams the area, stitches its frames, shows the panel and finishes on Return.
@MainActor
final class ScrollCapture {
    private let model = ScrollCaptureModel()
    private let screen: NSScreen
    /// The area in AppKit global points.
    private let area: CGRect
    private let scale: CGFloat
    private var panel: NSPanel?
    private var outline: ScrollOutlinePanel?
    private var stream: SCStream?
    private var sink: ScrollFrameSink?
    private var worker: ScrollStitchWorker?
    private var continuation: CheckedContinuation<(image: CGImage, scale: CGFloat)?, Never>?

    private static let keySlots = (finish: 1, cancel: 2)

    private init(screen: NSScreen, area: CGRect) {
        self.screen = screen
        self.area = area
        scale = screen.backingScaleFactor
    }

    /// Shows the panel beside `area` (AppKit global points) and returns the stitched image once the person presses
    /// Return, or nil when they cancel.
    static func run(area: CGRect) async throws -> (image: CGImage, scale: CGFloat)? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: area.midX, y: area.midY)) }) else {
            throw CaptureError.displayNotFound
        }
        return try await ScrollCapture(screen: screen, area: area).run()
    }

    private func run() async throws -> (image: CGImage, scale: CGFloat)? {
        try await startStream()
        showOutline()
        showPanel()
        registerKeys()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    // MARK: Stream

    private func startStream() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        // Shot's own windows, the panel above all, stay out of the frames.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = Geometry.displayLocalTopLeft(area, screenFrame: screen.frame)
        config.width = max(1, Int((area.width * scale).rounded()))
        config.height = max(1, Int((area.height * scale).rounded()))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        // A cursor drifting over the area would look like content that changes.
        config.showsCursor = false

        let worker = ScrollStitchWorker()
        self.worker = worker
        let sink = ScrollFrameSink(scale: scale) { [weak self] frame in
            let update = await worker.add(frame)
            await MainActor.run { self?.apply(update) }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        self.stream = stream
        // SCStream holds its outputs weakly.
        self.sink = sink
    }

    private func stopStream() async {
        let stream = stream
        self.stream = nil
        sink = nil
        try? await stream?.stopCapture()
    }

    private func apply(_ update: ScrollUpdate) {
        model.size = update.size
        if let preview = update.preview {
            model.preview = preview
        }
        switch update.outcome {
        case nil:
            break
        case .extended:
            model.status = .stitching
        case .unchanged:
            // Nothing new, so only a warning that has passed is cleared.
            if model.isWarning {
                model.status = .stitching
            }
        case .tooFar:
            model.status = .tooFar
        case .moving:
            model.status = .moving
        case .featureless:
            model.status = .featureless
        case .limit:
            model.status = .limit
        }
        outline?.warning = model.isWarning
    }

    // MARK: Finishing

    private func finish() {
        Task {
            await stopStream()
            let image = await worker?.result()?.cgImage
            close(result: image.map { ($0, scale) })
        }
    }

    private func cancel() {
        Task {
            await stopStream()
            close(result: nil)
        }
    }

    private func close(result: (image: CGImage, scale: CGFloat)?) {
        HotkeyCenter.shared.unregisterTemporary(slot: Self.keySlots.finish)
        HotkeyCenter.shared.unregisterTemporary(slot: Self.keySlots.cancel)
        panel?.orderOut(nil)
        outline?.orderOut(nil)
        panel = nil
        outline = nil
        continuation?.resume(returning: result)
        continuation = nil
    }

    /// Return and Esc work whichever app has the keyboard, since the person is scrolling in another one.
    private func registerKeys() {
        HotkeyCenter.shared.registerTemporary(KeyCombo(keyCode: UInt32(kVK_Return), modifiers: 0), slot: Self.keySlots.finish) { [weak self] in
            self?.finish()
        }
        HotkeyCenter.shared.registerTemporary(KeyCombo(keyCode: UInt32(kVK_Escape), modifiers: 0), slot: Self.keySlots.cancel) { [weak self] in
            self?.cancel()
        }
    }

    // MARK: Windows

    private func showOutline() {
        let panel = ScrollOutlinePanel(area: area)
        panel.orderFrontRegardless()
        outline = panel
    }

    private func showPanel() {
        let view = ScrollCapturePanelView(
            model: model,
            onDone: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() },
            onResize: { [weak self] height in self?.resizePanel(to: height) }
        )
        // The view reports its real height once it has laid out, so this only has to be close.
        let size = CGSize(width: ScrollCapturePanelView.width + 2 * Brutal.shadow, height: 330)
        let panel = NSPanel(contentRect: CGRect(origin: panelOrigin(size: size), size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSView(hosting: view)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Fits the panel to its content, keeping the top edge where it is.
    private func resizePanel(to height: CGFloat) {
        guard let panel, abs(panel.frame.height - height) > 0.5 else {
            return
        }
        var frame = panel.frame
        frame.origin.y = max(frame.origin.y + frame.height - height, screen.visibleFrame.minY + Brutal.shadow)
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    /// Beside the area, never over it: to the right if it fits, else left, below or above, else inside the screen's edge.
    private func panelOrigin(size: CGSize) -> CGPoint {
        let bounds = screen.visibleFrame
        let gap: CGFloat = 14
        func clampedY(_ y: CGFloat) -> CGFloat { min(max(y, bounds.minY + gap), bounds.maxY - size.height - gap) }
        func clampedX(_ x: CGFloat) -> CGFloat { min(max(x, bounds.minX + gap), bounds.maxX - size.width - gap) }
        if area.maxX + gap + size.width + gap <= bounds.maxX {
            return CGPoint(x: area.maxX + gap, y: clampedY(area.maxY - size.height))
        }
        if area.minX - gap - size.width - gap >= bounds.minX {
            return CGPoint(x: area.minX - gap - size.width, y: clampedY(area.maxY - size.height))
        }
        if area.minY - gap - size.height - gap >= bounds.minY {
            return CGPoint(x: clampedX(area.minX), y: area.minY - gap - size.height)
        }
        if area.maxY + gap + size.height + gap <= bounds.maxY {
            return CGPoint(x: clampedX(area.minX), y: area.maxY + gap)
        }
        return CGPoint(x: clampedX(bounds.maxX), y: clampedY(bounds.maxY))
    }
}

/// A click-through frame just outside the area, yellow while it captures and red when frames can't be matched.
private final class ScrollOutlinePanel: NSPanel {
    var warning = false {
        didSet { contentView?.needsDisplay = true }
    }

    init(area: CGRect) {
        let inset: CGFloat = 4
        super.init(contentRect: area.insetBy(dx: -inset, dy: -inset), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = OutlineView(owner: self)
    }

    private final class OutlineView: NSView {
        unowned let owner: ScrollOutlinePanel

        init(owner: ScrollOutlinePanel) {
            self.owner = owner
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            (owner.warning ? Brutal.redNS : Brutal.yellowNS).setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 3
            path.stroke()
        }
    }
}

private struct ScrollCapturePanelView: View {
    static let width: CGFloat = 288

    let model: ScrollCaptureModel
    let onDone: () -> Void
    let onCancel: () -> Void
    let onResize: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scrolling capture").font(.scaled(15, weight: .heavy))
                Spacer()
                BrutalChip(text: chipText, color: chipColor)
            }
            Text("\(Int(model.size.width)) × \(Int(model.size.height)) px")
                .font(.scaled(18, weight: .heavy))
                .monospacedDigit()
            preview
            if let message = model.message {
                Text(message)
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(Brutal.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brutalSurface(messageColor, radius: Brutal.Radius.button, shadow: 0, border: 2)
            }
            HStack {
                Button("Done ↩", action: onDone).buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                Button("Cancel", action: onCancel).buttonStyle(BrutalButtonStyle(compact: true))
            }
            .lineLimit(1)
        }
        .padding(14)
        .foregroundStyle(Brutal.ink)
        .frame(width: Self.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .glassCard()
        .padding(Brutal.shadow)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onResize($0) }
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            Brutal.well
            if let image = model.preview {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(height: 130)
        .inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.button, style: .circular), width: 2)
        .accessibilityLabel(Text("Preview of the newest part of the stitched image"))
    }

    private var chipText: LocalizedStringResource {
        switch model.status {
        case .ready: "Ready"
        case .stitching: "Live"
        case .tooFar: "Too fast"
        case .moving, .featureless: "Paused"
        case .limit: "Done"
        }
    }

    private var chipColor: Color {
        switch model.status {
        case .ready: Brutal.yellow
        case .stitching, .limit: Brutal.mint
        case .tooFar, .moving, .featureless: Brutal.red
        }
    }

    private var messageColor: Color {
        switch model.status {
        case .tooFar, .moving, .featureless: Brutal.red
        case .limit: Brutal.mint
        default: Brutal.paper
        }
    }
}
