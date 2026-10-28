import AppKit
import ApplicationServices
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
    case reachedEnd
    case limit
    case needsAccessibility
}

enum ScrollSpeed: Int, CaseIterable {
    case slow, normal, fast

    /// Pixels per 16 ms tick of the synthetic scroll wheel.
    var step: Int {
        switch self {
        case .slow: 5
        case .normal: 12
        case .fast: 24
        }
    }
}

@MainActor
@Observable
final class ScrollCaptureModel {
    var horizontal: Bool
    var scrollsForMe: Bool
    var speed: ScrollSpeed
    var status = ScrollCaptureStatus.ready
    var size = CGSize.zero
    var preview: CGImage?
    var isScrolling = false

    /// Set once the first new row arrives: the direction can't change after that.
    var hasStitched: Bool { size != .zero && status != .ready }

    private static let horizontalKey = "scrollCapture.horizontal"
    private static let autoKey = "scrollCapture.auto"
    private static let speedKey = "scrollCapture.speed"

    init() {
        let defaults = UserDefaults.standard
        horizontal = defaults.bool(forKey: Self.horizontalKey)
        scrollsForMe = defaults.bool(forKey: Self.autoKey)
        speed = ScrollSpeed(rawValue: defaults.integer(forKey: Self.speedKey)) ?? .normal
    }

    /// Remembers the choices for the next capture.
    func remember() {
        let defaults = UserDefaults.standard
        defaults.set(horizontal, forKey: Self.horizontalKey)
        defaults.set(scrollsForMe, forKey: Self.autoKey)
        defaults.set(speed.rawValue, forKey: Self.speedKey)
    }

    var message: LocalizedStringResource? {
        switch status {
        case .ready:
            if scrollsForMe {
                return "Press Scroll for me to start."
            }
            return horizontal ? "Scroll the content sideways." : "Scroll the content."
        case .stitching:
            return nil
        case .tooFar:
            return horizontal ? "Scrolled too far at once. Scroll back left a little and carry on." : "Scrolled too far at once. Scroll back up a little and carry on."
        case .moving:
            return "Something in the area keeps changing, so Shot can't line frames up. Pause the video or scroll past it."
        case .reachedEnd:
            return "Shot reached the end and stopped. Press Return to save."
        case .limit:
            return horizontal ? "That's as wide as Shot can stitch (30,000 px). Press Return to save." : "That's as tall as Shot can stitch (30,000 px). Press Return to save."
        case .needsAccessibility:
            return "To scroll for you, Shot needs the Accessibility permission in System Settings. Shot uses it only to scroll while you capture."
        }
    }

    var isWarning: Bool { status == .tooFar || status == .moving }
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
    private var outline: NSPanel?
    private var stream: SCStream?
    private var worker: ScrollStitchWorker?
    private var continuation: CheckedContinuation<(image: CGImage, scale: CGFloat)?, Never>?
    private var scrollTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    /// Frames in a row that showed nothing new while Shot scrolled: the end of the page.
    private var stillFrames = 0
    private var sawMovement = false
    private var generation = 0

    private static let keySlots = (finish: 1, cancel: 2)

    private init(screen: NSScreen, area: CGRect) {
        self.screen = screen
        self.area = area
        scale = screen.backingScaleFactor
    }

    /// Shows the panel over `area` (AppKit global points) and returns the stitched image once the person presses Return,
    /// or nil when they cancel.
    static func run(area: CGRect) async throws -> (image: CGImage, scale: CGFloat)? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: area.midX, y: area.midY)) }) else {
            throw CaptureError.displayNotFound
        }
        let capture = ScrollCapture(screen: screen, area: area)
        return try await capture.run()
    }

    private func run() async throws -> (image: CGImage, scale: CGFloat)? {
        try await startStream()
        showOutline()
        showPanel()
        registerKeys()
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return result
    }

    // MARK: Stream

    private func startStream() async throws {
        generation += 1
        let mine = generation
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

        let worker = ScrollStitchWorker(axis: model.horizontal ? .horizontal : .vertical)
        self.worker = worker
        let sink = ScrollFrameSink(scale: scale) { [weak self] frame in
            let update = await worker.add(frame)
            await MainActor.run { self?.apply(update, generation: mine) }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        self.stream = stream
        // Keeps the sink alive as long as the stream: SCStream holds its outputs weakly.
        sinkKeeper = sink
    }

    private var sinkKeeper: ScrollFrameSink?

    private func stopStream() async {
        let stream = stream
        self.stream = nil
        sinkKeeper = nil
        try? await stream?.stopCapture()
    }

    private func apply(_ update: ScrollUpdate, generation mine: Int) {
        guard mine == generation else {
            return
        }
        model.size = update.size
        if let preview = update.preview {
            model.preview = preview
        }
        guard model.status != .needsAccessibility else {
            return
        }
        switch update.outcome {
        case nil:
            break
        case .appended:
            sawMovement = true
            stillFrames = 0
            model.status = .stitching
        case .unchanged:
            if model.status == .tooFar || model.status == .moving {
                model.status = .stitching
            }
            if model.isScrolling, sawMovement {
                stillFrames += 1
                if stillFrames >= 6 {
                    stopScrolling()
                    model.status = .reachedEnd
                }
            }
        case .tooFar:
            model.status = .tooFar
            if model.isScrolling {
                // Back off, so the next frames overlap again.
                autoStep = max(2, autoStep / 2)
            }
        case .moving:
            model.status = .moving
        case .limit:
            stopScrolling()
            model.status = .limit
        }
        outline?.contentView?.needsDisplay = true
        (outline as? ScrollOutlinePanel)?.warning = model.isWarning
    }

    // MARK: Scrolling for the person

    private var autoStep = 12

    private func startScrolling() {
        guard AXIsProcessTrusted() else {
            model.status = .needsAccessibility
            // Asks the system to list Shot in the Accessibility pane, then carries on once it's switched on.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            permissionTask?.cancel()
            permissionTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if AXIsProcessTrusted() {
                        self?.model.status = .ready
                        self?.startScrolling()
                        return
                    }
                }
            }
            return
        }
        guard !model.isScrolling else {
            return
        }
        model.isScrolling = true
        stillFrames = 0
        autoStep = model.speed.step
        let target = CGPoint(x: area.midX, y: (NSScreen.screens.first?.frame.height ?? screen.frame.maxY) - area.midY)
        CGWarpMouseCursorPosition(target)
        scrollTask = Task { [weak self] in
            while !Task.isCancelled, let self, self.model.isScrolling {
                let step = Int32(-self.autoStep)
                let horizontal = self.model.horizontal
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: horizontal ? 0 : step, wheel2: horizontal ? step : 0, wheel3: 0)
                event?.location = target
                event?.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopScrolling() {
        model.isScrolling = false
        scrollTask?.cancel()
        scrollTask = nil
    }

    // MARK: Finishing

    private func finish() {
        Task {
            stopScrolling()
            await stopStream()
            let bitmap = await worker?.result()
            let image = bitmap?.cgImage
            close(result: image.map { ($0, scale) })
        }
    }

    private func cancel() {
        Task {
            stopScrolling()
            await stopStream()
            close(result: nil)
        }
    }

    private func close(result: (image: CGImage, scale: CGFloat)?) {
        model.remember()
        permissionTask?.cancel()
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
            guard let self else {
                return
            }
            if model.isScrolling {
                stopScrolling()
            } else {
                cancel()
            }
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
            onToggleScrolling: { [weak self] in
                guard let self else {
                    return
                }
                model.isScrolling ? stopScrolling() : startScrolling()
            },
            onDirectionChange: { [weak self] in
                guard let self else {
                    return
                }
                // A new direction starts a new image, so the stream restarts with a stitcher for it.
                Task {
                    await self.stopStream()
                    self.model.size = .zero
                    self.model.preview = nil
                    self.model.status = .ready
                    do {
                        try await self.startStream()
                    } catch {
                        log.error("Restarting the scrolling stream failed: \(error.localizedDescription, privacy: .public)")
                        Toast.error(error.localizedDescription)
                        self.cancel()
                    }
                }
            },
            onOpenAccessibility: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            },
            onScrollMyself: { [weak self] in
                self?.permissionTask?.cancel()
                self?.model.scrollsForMe = false
                self?.model.status = .ready
            }
        )
        let size = CGSize(width: ScrollCapturePanelView.width, height: ScrollCapturePanelView.height)
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
    static let height: CGFloat = 440

    let model: ScrollCaptureModel
    let onDone: () -> Void
    let onCancel: () -> Void
    let onToggleScrolling: () -> Void
    let onDirectionChange: () -> Void
    let onOpenAccessibility: () -> Void
    let onScrollMyself: () -> Void

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scrolling capture").font(.scaled(15, weight: .heavy))
                Spacer()
                BrutalChip(text: chipText, color: chipColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Direction").sectionCaption()
                BrutalSegmented(selection: $model.horizontal, options: [(false, "Vertical"), (true, "Horizontal")], color: Brutal.yellow)
                    .disabled(model.hasStitched)
                    .onChange(of: model.horizontal) { onDirectionChange() }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Who scrolls").sectionCaption()
                BrutalSegmented(selection: $model.scrollsForMe, options: [(false, "I scroll"), (true, "Shot scrolls")], color: Brutal.yellow)
            }
            if model.scrollsForMe {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speed").sectionCaption()
                    BrutalSegmented(selection: $model.speed, options: [(ScrollSpeed.slow, "Slow"), (.normal, "Normal"), (.fast, "Fast")], color: Brutal.yellow)
                }
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
            Spacer(minLength: 0)
            buttons
        }
        .padding(14)
        .foregroundStyle(Brutal.ink)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .glassCard()
        .padding(Brutal.shadow)
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
        .frame(height: 120)
        .inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.button, style: .circular), width: 2)
        .accessibilityLabel(Text("Preview of the stitched image"))
    }

    @ViewBuilder private var buttons: some View {
        if model.status == .needsAccessibility {
            HStack {
                Button("Open System Settings", action: onOpenAccessibility).buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                Button("Scroll myself", action: onScrollMyself).buttonStyle(BrutalButtonStyle(compact: true))
            }
        } else {
            HStack {
                Button("Done ↩", action: onDone).buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                if model.scrollsForMe {
                    Button(model.isScrolling ? "Stop" : "Scroll for me", action: onToggleScrolling).buttonStyle(BrutalButtonStyle(compact: true))
                }
                Button("Cancel ⎋", action: onCancel).buttonStyle(BrutalButtonStyle(compact: true))
            }
        }
    }

    private var chipText: LocalizedStringResource {
        switch model.status {
        case .ready: "Ready"
        case .stitching: model.isScrolling ? "Auto" : "Live"
        case .tooFar: "Too fast"
        case .moving: "Paused"
        case .reachedEnd, .limit: "Done"
        case .needsAccessibility: "Permission"
        }
    }

    private var chipColor: Color {
        switch model.status {
        case .ready, .needsAccessibility: Brutal.yellow
        case .stitching, .reachedEnd, .limit: Brutal.mint
        case .tooFar, .moving: Brutal.red
        }
    }

    private var messageColor: Color {
        switch model.status {
        case .tooFar, .moving: Brutal.red
        case .reachedEnd, .limit: Brutal.mint
        default: Brutal.paper
        }
    }
}
