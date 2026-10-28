import AppKit
import os
import ScreenCaptureKit
import ShotCore
import SwiftUI

private let log = Logger.shot("scrolling")

/// What the scrolling capture panel shows.
@MainActor
@Observable
final class ScrollCaptureModel {
    var status: ScrollCaptureStatus = .ready
    /// The image so far, in pixels.
    var size = CGSize.zero
    /// Where the area is within the image, in pixels from its top left.
    var viewport = CGRect.zero
    /// The image so far at an eighth of its size, clear where nothing has been seen.
    var preview: CGImage?
}

/// Runs one scrolling capture: streams the area while the person scrolls it themselves, stitches the frames as they
/// come, and shows the panel beside the area. Return or Done finishes, Esc or Cancel discards. Shot never scrolls for
/// the person, so this needs only the Screen Recording access every capture has.
@MainActor
final class ScrollingCaptureController: NSObject {
    enum Result: @unchecked Sendable {
        case finished(image: CGImage, scale: CGFloat)
        case cancelled
    }

    private let screen: NSScreen
    /// AppKit global rect.
    private let region: CGRect
    private let scale: Int
    private let model = ScrollCaptureModel()
    private var border: RecordingBorderPanel?
    private var panel: ScrollCapturePanel?
    private var stream: SCStream?
    private var sink: ScrollFrameSink?
    private var hotkeys: TemporaryHotkeys?
    private var continuation: CheckedContinuation<Result, Never>?
    private var ending = false

    init(screen: NSScreen, region: CGRect) {
        self.screen = screen
        self.region = region
        scale = max(1, Int(screen.backingScaleFactor.rounded()))
    }

    /// Streams the area until Return or Esc. Throws when the stream can't start.
    func run() async throws -> Result {
        let width = Int((region.width * CGFloat(scale)).rounded()), height = Int((region.height * CGFloat(scale)).rounded())
        guard width >= 16, height >= 16 else {
            throw ScrollCaptureError.tooSmall
        }
        let sink = ScrollFrameSink(scale: scale, model: model)
        self.sink = sink
        showPanels()
        do {
            try await startStream(sink, width: width, height: height)
        } catch {
            hidePanels()
            throw error
        }
        // The panel takes no keyboard focus, so Return and Esc work while the content's app has the keyboard.
        let returnKey = KeyCombo(keyCode: 36, modifiers: 0), enterKey = KeyCombo(keyCode: 76, modifiers: 0), escape = KeyCombo(keyCode: 53, modifiers: 0)
        hotkeys = HotkeyCenter.shared.registerTemporary(combos: [returnKey, enterKey, escape]) { [weak self] combo in
            if combo == escape {
                self?.cancel()
            } else {
                self?.finish()
            }
        }
        log.notice("Scrolling capture started: \(width)x\(height) at \(self.scale)x")
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Stops and hands back the image so far.
    func finish() {
        end(discard: false)
    }

    /// Stops and keeps nothing.
    func cancel() {
        end(discard: true)
    }

    private func end(discard: Bool) {
        guard !ending, let continuation else {
            return
        }
        ending = true
        self.continuation = nil
        hotkeys?.unregister()
        hotkeys = nil
        hidePanels()
        let stream = stream
        self.stream = nil
        let sink = sink
        let scale = CGFloat(scale)
        Task {
            do {
                try await stream?.stopCapture()
            } catch {
                log.error("stopCapture failed: \(error.localizedDescription, privacy: .public)")
            }
            if discard {
                log.notice("Scrolling capture cancelled")
                continuation.resume(returning: .cancelled)
                return
            }
            guard let image = await sink?.result() else {
                Toast.error("Nothing was captured. Try again.")
                continuation.resume(returning: .cancelled)
                return
            }
            log.notice("Scrolling capture finished: \(image.image.width)x\(image.image.height)")
            continuation.resume(returning: .finished(image: image.image, scale: scale))
        }
    }

    // MARK: Stream

    private func startStream(_ sink: ScrollFrameSink, width: Int, height: Int) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        // Shot's own windows, the panel and outline included, never appear in the frames.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = Geometry.displayLocalTopLeft(region, screenFrame: screen.frame)
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        self.stream = stream
    }

    // MARK: Panels

    private func showPanels() {
        let border = RecordingBorderPanel(region: region, style: .outline(Self.outlineColor(for: model.status)))
        border.orderFrontRegardless()
        self.border = border
        let panel = ScrollCapturePanel(model: model, region: region, screen: screen, actions: .init(
            done: { [weak self] in self?.finish() },
            cancel: { [weak self] in self?.cancel() }
        ))
        panel.orderFrontRegardless()
        self.panel = panel
        observeStatus()
    }

    private func hidePanels() {
        border?.orderOut(nil)
        border = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Keeps the outline's colour with the status.
    private func observeStatus() {
        withObservationTracking {
            _ = model.status
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let border = self.border else {
                    return
                }
                border.setStyle(.outline(Self.outlineColor(for: self.model.status)))
                self.observeStatus()
            }
        }
    }

    static func outlineColor(for status: ScrollCaptureStatus) -> NSColor {
        switch status {
        case .ready: Brutal.inkNS
        case .live: Brutal.mintNS
        case .sizeLimit: Brutal.yellowNS
        case .tooFar, .changing, .notEnough: Brutal.redNS
        }
    }
}

extension ScrollingCaptureController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            log.error("Scrolling capture stream stopped: \(error.localizedDescription, privacy: .public)")
            Toast.error("The capture stopped: \(error.localizedDescription)")
            self.stream = nil
            cancel()
        }
    }
}

enum ScrollCaptureError: LocalizedError {
    case tooSmall

    var errorDescription: String? {
        switch self {
        case .tooSmall: String(localized: "That area is too small to capture. Drag out a bigger one.")
        }
    }
}

/// Takes the stream's frames on its own queue, stitches them, and keeps the panel's model up to date: the status and
/// size after every frame, the preview a few times a second.
private final class ScrollFrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "Shot.scrolling", qos: .userInteractive)
    private let scale: Int
    private let model: ScrollCaptureModel
    /// Made on the first frame, at the frames' size; only used on `queue`.
    private var stitcher: ScrollStitcher?
    private var previewShown = ContinuousClock.now
    private var previewStale = false
    private var frames = 0

    init(scale: Int, model: ScrollCaptureModel) {
        self.scale = scale
        self.model = model
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, Self.isComplete(sampleBuffer), let buffer = sampleBuffer.imageBuffer else {
            return
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return
        }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width >= 16, height >= 16 else {
            return
        }
        if stitcher == nil {
            stitcher = ScrollStitcher(width: width, height: height, scale: scale, byteOrder: .bgra)
        }
        guard let stitcher else {
            return
        }
        let frame = ScrollFrame(width: width, height: height, bytesPerRow: bytesPerRow, pixels: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height))
        let start = ContinuousClock.now
        let update = stitcher.process(frame)
        frames += 1
        if frames % 30 == 0 {
            log.debug("Frame \(self.frames) took \(ContinuousClock.now - start, privacy: .public): \(String(describing: update.status), privacy: .public) \(Int(update.size.width))x\(Int(update.size.height))")
        }
        previewStale = previewStale || update.changed
        var preview: SendableImage?
        if previewStale, ContinuousClock.now - previewShown > .milliseconds(120), let image = stitcher.preview() {
            preview = SendableImage(image)
            previewShown = ContinuousClock.now
            previewStale = false
        }
        Task { @MainActor [model] in
            model.status = update.status
            model.size = update.size
            model.viewport = update.viewport
            if let preview {
                model.preview = preview.image
            }
        }
    }

    /// The stitched image, once every frame so far has been taken.
    func result() async -> SendableImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.stitcher?.image(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)).map(SendableImage.init))
            }
        }
    }

    private static func isComplete(_ frame: CMSampleBuffer) -> Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        return attachments?.first?[.status] as? Int == SCFrameStatus.complete.rawValue
    }
}

// MARK: Panel

/// The panel beside the area: a status chip and the size, a preview of the image so far with the unseen parts hatched
/// and the area outlined, one message when something needs attention, and Done and Cancel. It takes no keyboard
/// focus, so the content's app keeps scrolling with the keyboard, and it grows to fit what it shows.
private final class ScrollCapturePanel: NSPanel {
    struct Actions {
        let done: @MainActor () -> Void
        let cancel: @MainActor () -> Void
    }

    private let region: CGRect
    private let room: CGRect

    @MainActor
    init(model: ScrollCaptureModel, region: CGRect, screen: NSScreen, actions: Actions) {
        self.region = region
        room = screen.visibleFrame
        let size = NSSize(width: ScrollCaptureView.width + 4, height: 200)
        super.init(contentRect: NSRect(origin: ScrollCapturePanelPlacement.origin(for: size, region: region, visible: screen.visibleFrame), size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSView(hosting: ScrollCaptureView(model: model, actions: actions) { [weak self] size in
            self?.fit(size)
        })
    }

    override var canBecomeKey: Bool { false }

    /// Resizes to `size`, keeping the panel where the placement put it: beside the area, lined up with its top.
    private func fit(_ size: CGSize) {
        let wanted = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted != frame.size, wanted.width > 0, wanted.height > 0 else {
            return
        }
        setFrame(NSRect(origin: ScrollCapturePanelPlacement.origin(for: wanted, region: region, visible: room), size: wanted), display: true)
    }
}

private struct ScrollCaptureView: View {
    static let width: CGFloat = 268

    let model: ScrollCaptureModel
    let actions: ScrollCapturePanel.Actions
    let onSize: (CGSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrutalChip(text: model.status.title, color: chipColor)
                BrutalChip(text: sizeText)
                Spacer(minLength: 0)
            }
            ScrollPreview(image: model.preview, size: model.size, viewport: model.viewport)
            if let message = model.status.message {
                Text(message)
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { actions.cancel() }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .brutalTip("Cancel (Esc)")
                Spacer()
                Button {
                    actions.done()
                } label: {
                    Label("Done", systemImage: "checkmark").labelStyle(.titleAndIcon).fixedSize()
                }
                .buttonStyle(BrutalButtonStyle(color: Brutal.mint, compact: true))
                .brutalTip("Save and copy (Return)")
            }
        }
        .padding(14)
        .frame(width: Self.width)
        .brutalSurface(Brutal.paper.opacity(0.72), glass: true, radius: 14, shadow: 4)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var chipColor: Color {
        switch model.status {
        case .ready: Brutal.paper
        case .live: Brutal.mint
        case .sizeLimit: Brutal.yellow
        case .tooFar, .changing, .notEnough: Brutal.red
        }
    }

    private var sizeText: String {
        "\(Int(model.size.width).formatted()) × \(Int(model.size.height).formatted())"
    }
}

/// The image so far, scaled to fit, over hatching that shows through where nothing has been seen, with the area
/// outlined so the person can tell where they are and scroll back to fill a gap.
private struct ScrollPreview: View {
    let image: CGImage?
    let size: CGSize
    let viewport: CGRect

    private static let maxWidth = ScrollCaptureView.width - 28
    private static let maxHeight: CGFloat = 220

    var body: some View {
        let fitted = fittedSize
        let scale = size.width > 0 ? fitted.width / size.width : 1
        ZStack(alignment: .topLeading) {
            Hatching()
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: fitted.width, height: fitted.height)
            }
            if size.width > 0 {
                Color.clear
                    .inkBorder(Rectangle(), width: 2, color: Brutal.sky)
                    .frame(width: max(4, viewport.width * scale), height: max(4, viewport.height * scale))
                    .offset(x: viewport.minX * scale, y: viewport.minY * scale)
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.chip, style: .circular), width: 2)
        .accessibilityLabel(Text("Preview of the image so far"))
    }

    /// The preview's size: the image's shape within the panel, and a square before there is one.
    private var fittedSize: CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: Self.maxWidth, height: Self.maxWidth * 0.6)
        }
        let scale = min(Self.maxWidth / size.width, Self.maxHeight / size.height)
        return CGSize(width: max(24, (size.width * scale).rounded()), height: max(24, (size.height * scale).rounded()))
    }
}

/// Diagonal hatching, which marks what hasn't been seen.
private struct Hatching: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Brutal.well))
            var path = Path()
            let step: CGFloat = 8
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(Brutal.ink.opacity(0.18)), lineWidth: 1)
        }
    }
}
