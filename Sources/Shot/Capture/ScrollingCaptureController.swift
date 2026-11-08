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
    /// Frames the image is built from so far.
    var framesKept = 0
    /// Whether a sticky header was found, which the image shows once.
    var hasStickyHeader = false
    /// The side the image is growing on, where the preview shows the yellow edge and "Not yet".
    var frontier = ScrollFrontier.bottom
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
        let mainWindows = content.windows.filter { $0.windowID == MainWindowController.windowID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: mainWindows)
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
        let border = RecordingBorderPanel(region: region, style: .scrolling)
        border.orderFrontRegardless()
        self.border = border
        let panel = ScrollCapturePanel(model: model, region: region, screen: screen, actions: .init(
            done: { [weak self] in self?.finish() },
            cancel: { [weak self] in self?.cancel() }
        ))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hidePanels() {
        border?.orderOut(nil)
        border = nil
        panel?.orderOut(nil)
        panel = nil
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
            model.frontier = ScrollFrontier.after(model.frontier, oldSize: model.size, newSize: update.size, viewport: update.viewport)
            model.size = update.size
            model.framesKept = update.framesKept
            model.hasStickyHeader = update.hasStickyHeader
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

/// The panel beside the area (Capture › Scrolling capture): a status heading, a preview of the image so far with what
/// isn't covered yet hatched and a yellow edge where the area is, the size, frames kept and whether a sticky header
/// was found, a warning card when something needs attention, and Cancel and Done. Unlike the other floating panels it
/// follows the appearance, as the board draws it. It takes no keyboard focus, so the content's app keeps scrolling
/// with the keyboard, and it grows to fit what it shows.
private final class ScrollCapturePanel: FloatingPanelWindow {
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
        let size = NSSize(width: ScrollCaptureView.width, height: 420)
        super.init(contentRect: NSRect(origin: ScrollCapturePanelPlacement.origin(for: size, region: region, visible: screen.visibleFrame), size: size))
        level = .statusBar
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
    static let width: CGFloat = 300
    static let radius: CGFloat = 16

    let model: ScrollCaptureModel
    let actions: ScrollCapturePanel.Actions
    let onSize: (CGSize) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Brutal.separator.frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                ScrollPreview(model: model)
                facts
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Brutal.separator.frame(height: 1)
            footer
        }
        .frame(width: Self.width)
        .modifier(ScrollPanelSurface(shape: RoundedRectangle(cornerRadius: Self.radius, style: .circular)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Scrolling capture"))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .onChange(of: model.status) { _, status in
            if let warning = status.warning {
                AccessibilityNotification.Announcement("\(warning.title). \(warning.advice)").post()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatusDot(live: model.status == .live)
                Text(model.status.heading)
                    .font(.scaled(14, weight: .bold))
                    .foregroundStyle(Brutal.ink)
            }
            Text(model.status.detail)
                .font(.scaled(12))
                .foregroundStyle(Brutal.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Fact(label: "Size") {
                Text(sizeText).font(Brutal.numbers)
            }
            Fact(label: "Frames kept") {
                Text(model.framesKept.formatted()).font(Brutal.numbers)
            }
            Fact(label: "Sticky header") {
                Text(model.hasStickyHeader ? "Kept once" : "None found").font(.scaled(12, weight: .semibold))
            }
            Spacer(minLength: 0)
            if let warning = model.status.warning {
                WarningCard(title: warning.title, advice: warning.advice)
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Esc discards")
                .font(Brutal.caption)
                .foregroundStyle(Brutal.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel") { actions.cancel() }
                .buttonStyle(BrutalButtonStyle())
                .brutalTip("Discard the capture", key: "Esc")
            Button {
                actions.done()
            } label: {
                HStack(spacing: 8) {
                    Text("Done")
                    Text(verbatim: "↩").font(.scaled(11)).opacity(0.7).accessibilityHidden(true)
                }
                .fixedSize()
            }
            .buttonStyle(BrutalButtonStyle(.main))
            .accessibilityLabel(Text("Done"))
            .brutalTip("Save and copy", key: "↩")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sizeText: String {
        "\(Int(model.size.width).formatted()) × \(Int(model.size.height).formatted())"
    }
}

private let scrollPanelFill = Color(light: Color(red: 250 / 255, green: 249 / 255, blue: 246 / 255), dark: Color(hex: 0x2C2C30))

/// The panel's surface: the board's warm white in light, the popover grey in dark. It's solid, unlike the board's 96%,
/// because the panel sits beside content that's moving and text behind it showed through. The system window shadow
/// goes round it.
private struct ScrollPanelSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let increased = contrast == .increased
        content
            .background(scrollPanelFill, in: shape)
            .inkBorder(shape, width: 0.5, color: Color(light: .black.opacity(increased ? 0.5 : 0.25), dark: .white.opacity(increased ? 0.4 : 0.14)))
    }
}

/// Green with a soft ring while frames are being added; grey otherwise, since the heading and warning card say why.
private struct StatusDot: View {
    let live: Bool

    var body: some View {
        Circle()
            .fill(live ? Brutal.success : Brutal.tertiaryText)
            .frame(width: 8, height: 8)
            .background(Circle().fill(Brutal.success.opacity(live ? 0.22 : 0)).frame(width: 14, height: 14))
            .accessibilityHidden(true)
    }
}

/// A label over its value, read by VoiceOver as one.
private struct Fact<Value: View>: View {
    let label: LocalizedStringResource
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.scaled(12))
                .foregroundStyle(Brutal.tertiaryText)
            value
                .foregroundStyle(Brutal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The yellow card for a status that needs attention.
private struct WarningCard: View {
    let title: String
    let advice: String
    @Environment(\.colorSchemeContrast) private var contrast

    private static let fill = Color(light: Color(hex: 0xFFF4D6), dark: Color(hex: 0xF2CC4A).opacity(0.14))
    private static let text = Color(light: Color(hex: 0x6B4F00), dark: Color(hex: 0xF2CC4A))

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.control, style: .circular)
        let edge = contrast == .increased ? 0.6 : 0.25
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.scaled(12, weight: .semibold))
            Text(advice).font(.scaled(12)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Self.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Self.fill, in: shape)
        .inkBorder(shape, width: 1, color: Color(light: Color(hex: 0x8A6A00).opacity(edge), dark: Color(hex: 0xF2CC4A).opacity(edge + 0.1)))
        .accessibilityElement(children: .combine)
    }
}

/// The image so far over hatching, which shows through where nothing has been seen and fills the room past the
/// frontier marked "Not yet", with a yellow edge where the area is so the person can tell how far they've come.
private struct ScrollPreview: View {
    let model: ScrollCaptureModel

    static let size = CGSize(width: 150, height: 280)
    private static let reserve: CGFloat = 40

    var body: some View {
        let layout = ScrollPreviewLayout(size: model.size, viewport: model.viewport, frontier: model.frontier, box: Self.size, reserve: Self.reserve, growing: model.status != .sizeLimit)
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular)
        ZStack(alignment: .topLeading) {
            Hatching()
            if let image = model.preview {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: layout.image.width, height: layout.image.height)
                    .offset(x: layout.image.minX, y: layout.image.minY)
            }
            if let notYet = layout.notYet, notYet.height >= 22, notYet.width >= 52 {
                Text("Not yet")
                    .font(.scaled(10, weight: .semibold))
                    .foregroundStyle(Brutal.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Brutal.window, in: RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular))
                    .frame(width: notYet.width, height: notYet.height)
                    .offset(x: notYet.minX, y: notYet.minY)
            }
            if let edge = layout.edge {
                Brutal.accent
                    .inkBorder(Rectangle(), width: 0.5, color: Brutal.line)
                    .frame(width: edge.width, height: edge.height)
                    .offset(x: edge.minX, y: edge.minY)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipShape(shape)
        .depth(.group, fill: Brutal.group, radius: Brutal.Radius.group)
        .accessibilityElement()
        .accessibilityLabel(Text("Preview of the image so far"))
    }
}

/// Diagonal stripes on the window colour, which mark what hasn't been seen.
private struct Hatching: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Brutal.window))
            var path = Path()
            // 6 pt stripes every 12 pt, measured across them, as the board's 135° gradient draws them.
            let step = 12 * 2.squareRoot()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(Brutal.ink.opacity(contrast == .increased ? 0.22 : 0.1)), lineWidth: 6)
        }
    }
}
