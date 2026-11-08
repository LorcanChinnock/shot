import AppKit
import AVFoundation
import Observation
import os
import ShotCore
import SwiftUI

private let log = Logger.shot("recording")

@MainActor
@Observable
final class RecordingSetupModel {
    var mode: CaptureTarget
    var pixelSize: CGSize = .zero
    var cameraOn: Bool
    var microphoneOn: Bool
    var cursorOn: Bool
    /// Sound from other apps on the Mac.
    var systemAudioOn: Bool
    /// The frame rate this recording asks for, one of `frameRates`.
    var fps: Int
    /// The rates the screen being recorded can offer.
    var frameRates: [Int] = RecordingFrameRate.all
    /// The microphone picked in Settings, or the system default's name.
    let microphoneName: String
    /// The size and ratio chip's text above the frame.
    var frameLabel = ""
    /// Set when recording a single window rather than a screen area.
    var windowID: CGWindowID?
    /// Set with `windowID` when recording just a browser window's page.
    var pageInsets: PageInsets?
    /// Seconds left while counting down.
    var countdown: Int? {
        didSet { onCountdown(countdown) }
    }
    /// How long the countdown runs once Record is pressed; 0 starts at once.
    var countdownSeconds: Int
    @ObservationIgnored private let onCountdown: (Int?) -> Void

    init(mode: CaptureTarget, prefs: Preferences, countdownSeconds: Int, onCountdown: @escaping (Int?) -> Void) {
        self.mode = mode
        self.countdownSeconds = countdownSeconds
        self.onCountdown = onCountdown
        cameraOn = prefs.recordCamera
        microphoneOn = prefs.recordMicrophone
        cursorOn = prefs.recordShowsCursor
        systemAudioOn = prefs.recordSystemAudio
        fps = prefs.recordingFPS
        microphoneName = CaptureDevices.device(id: prefs.microphoneDeviceID, for: .audio)?.localizedName ?? String(localized: "Microphone")
    }

    /// Offers the rates `screen` can refresh at, and steps the chosen one down to the fastest of them when it can't.
    func fitFrameRate(to screen: NSScreen) {
        let display = screen.maximumFramesPerSecond
        frameRates = RecordingFrameRate.offered(maximumDisplayRate: display)
        fps = RecordingFrameRate.effective(setting: fps, displayRate: display)
    }

    var options: Recorder.Options {
        .init(camera: cameraOn, microphone: microphoneOn, showsCursor: cursorOn, systemAudio: systemAudioOn, fps: fps, windowID: windowID, pageInsets: pageInsets)
    }
}

/// Starts a recording of a picked area, first showing the setup panel and counting down when `RecordingStart` asks for them.
/// The setup panel lets the user adjust the frame and this recording's options, then press Record.
@MainActor
final class RecordingSetupController {
    /// Only crosses the continuation on the main actor.
    enum Result: @unchecked Sendable {
        case start(screen: NSScreen, region: CGRect, options: Recorder.Options)
        case cancel
    }

    private let model: RecordingSetupModel
    private var screen: NSScreen
    private var region: CGRect
    /// The width over height the frame's handles keep, when the area was picked with one.
    private var ratio: CGFloat?
    private var frame: SetupFramePanel?
    private var handles: [RegionHandle: HandlePanel] = [:]
    private var bar: SetupBarPanel?
    private var countdownPanel: CountdownPanel?
    private var countdownTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<Result, Never>?
    private let showsSetup: Bool
    /// True while the camera starts before an automatic start, so a record press can't start with options it may still change.
    private var preparing = false

    /// `onCountdown` gets the seconds left as the countdown runs, and `nil` when it ends.
    init(mode: CaptureTarget, screen: NSScreen, region: CGRect, windowID: CGWindowID?, pageInsets: PageInsets?, ratio: CGFloat?, start: RecordingStart, onCountdown: @escaping (Int?) -> Void) {
        model = RecordingSetupModel(mode: mode, prefs: Preferences(), countdownSeconds: start.countdown, onCountdown: onCountdown)
        showsSetup = start.showsSetup
        self.screen = screen
        self.region = region
        self.ratio = ratio
        model.windowID = windowID
        model.pageInsets = pageInsets
        model.fitFrameRate(to: screen)
    }

    /// What `pickRegion` picked; `optionHeld` is whether ⌥ was held as the pick ended.
    struct Pick {
        let screen: NSScreen
        let region: CGRect
        let windowID: CGWindowID?
        var pageInsets: PageInsets?
        let ratio: CGFloat?
        var optionHeld = false
        /// Seconds chosen on the overlay to wait before recording; 0 is off.
        var delay = 0
        /// What was picked, which can differ from what the overlay opened on after Tab.
        var target = CaptureTarget.area
    }

    /// Lets the user pick an area or window with the live overlay, or takes the screen under the pointer.
    /// `remembering` keeps the target the overlay ends on, for the next recording to open on. `mode` of `.screen` takes
    /// the screen at once unless `opensOverlayOnScreen`, as when Full Screen was only the last thing picked.
    static func pickRegion(mode: CaptureTarget, offersDelay: Bool = true, remembering: Bool = false, opensOverlayOnScreen: Bool = false) async -> Pick? {
        let screens = NSScreen.screens
        if mode == .screen, !opensOverlayOnScreen {
            let screen = NSScreen.underPointer ?? screens[0]
            return Pick(screen: screen, region: screen.fullCaptureFrame, windowID: nil, ratio: nil, target: .screen)
        }
        let displays = screens.map { OverlayDisplay(frame: $0.frame, scale: $0.backingScaleFactor, image: nil) }
        let windows = WindowCapturer.onScreenWindows()
        let result = await SelectionOverlayController.select(displays: displays, target: mode, offersDelay: offersDelay, recording: true, windows: windows, isLive: true)
        if remembering {
            Preferences().recordTarget = result.target
        }
        guard let selection = result.selection else {
            return nil
        }
        let optionHeld = result.modifiers.contains(.option)
        switch selection {
        case let .area(index, rect, ratio):
            let screen = screens[index]
            return Pick(screen: screen, region: rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), windowID: nil, ratio: ratio, optionHeld: optionHeld, delay: result.delay, target: .area)
        case let .window(info):
            let (screen, region) = region(of: info)
            return Pick(screen: screen, region: region, windowID: info.windowID, ratio: nil, optionHeld: optionHeld, delay: result.delay, target: .window)
        case let .page(info, insets):
            let (screen, region) = region(of: info, insets: insets)
            return Pick(screen: screen, region: region, windowID: info.windowID, pageInsets: insets, ratio: nil, optionHeld: optionHeld, delay: result.delay, target: .window)
        case let .fullDisplay(index):
            return Pick(screen: screens[index], region: screens[index].fullCaptureFrame, windowID: nil, ratio: nil, optionHeld: optionHeld, delay: result.delay, target: .screen)
        }
    }

    /// The screen a window is mostly on, by its centre, and the part of the window on that screen, as an AppKit global rect.
    static func region(of window: WindowInfo, insets: PageInsets? = nil) -> (screen: NSScreen, region: CGRect) {
        let screens = NSScreen.screens
        let frame = Geometry.flip(insets?.page(in: window.frame) ?? window.frame, primaryHeight: screens.first?.frame.height ?? 0)
        let screen = screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) } ?? screens[0]
        return (screen, frame.intersection(screen.frame))
    }

    func run() async -> Result {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task {
                if showsSetup {
                    await showSetup(placeCamera: true)
                } else {
                    if model.cameraOn {
                        preparing = true
                        await showCamera()
                        preparing = false
                    }
                    confirm()
                }
            }
        }
    }

    // MARK: Actions

    /// Starts the countdown, or recording when there is none; the record hotkey and Return also call this.
    func confirm() {
        guard model.countdown == nil, continuation != nil, !preparing else {
            return
        }
        setSetupVisible(false)
        guard model.countdownSeconds > 0 else {
            finish(.start(screen: screen, region: region, options: model.options))
            return
        }
        model.countdown = model.countdownSeconds
        let panel = CountdownPanel(kind: .recording, total: model.countdownSeconds, center: CGPoint(x: region.midX, y: region.midY), remaining: { [model] in model.countdown }) { [weak self] in
            self?.cancelCountdown()
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        countdownPanel = panel
        countdownTask = Task {
            for remaining in stride(from: model.countdownSeconds, through: 1, by: -1) {
                model.countdown = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    return
                }
            }
            finish(.start(screen: screen, region: region, options: model.options))
        }
    }

    func cancel() {
        CameraBubble.shared.hide()
        finish(.cancel)
    }

    /// Goes back to the setup panel, or cancels the recording when it wasn't shown.
    private func cancelCountdown() {
        guard showsSetup else {
            cancel()
            return
        }
        countdownTask?.cancel()
        countdownTask = nil
        countdownPanel?.orderOut(nil)
        countdownPanel = nil
        model.countdown = nil
        setSetupVisible(true)
    }

    private func finish(_ result: Result) {
        countdownTask?.cancel()
        countdownPanel?.orderOut(nil)
        countdownPanel = nil
        model.countdown = nil
        tearDownSetup()
        continuation?.resume(returning: result)
        continuation = nil
    }

    func switchMode(_ mode: CaptureTarget) async {
        guard model.countdown == nil else {
            return
        }
        setSetupVisible(false)
        if let picked = await Self.pickRegion(mode: mode, remembering: true) {
            model.mode = picked.target
            model.countdownSeconds = RecordingStart.after(adjustBeforeRecording: false, countdown: picked.delay, optionHeld: false).countdown
            screen = picked.screen
            model.fitFrameRate(to: picked.screen)
            region = picked.region
            model.windowID = picked.windowID
            model.pageInsets = picked.pageInsets
            ratio = picked.ratio
            tearDownSetup()
            await showSetup(placeCamera: true)
        } else {
            setSetupVisible(true)
        }
    }

    func toggleCamera() async {
        model.cameraOn.toggle()
        if model.cameraOn {
            await showCamera()
        } else {
            CameraBubble.shared.hide()
        }
    }

    func toggleMicrophone() async {
        model.microphoneOn.toggle()
        await updateMicrophonePreview()
    }

    func toggleCursor() {
        model.cursorOn.toggle()
    }

    func toggleSystemAudio() {
        model.systemAudioOn.toggle()
    }

    func setFrameRate(_ fps: Int) {
        model.fps = fps
    }

    /// Runs the microphone while the bar shows it on, so its level meter moves as you speak. It stops before a countdown
    /// or the recording, which opens the microphone itself. Turning it on is also when macOS asks for permission; without
    /// it, the microphone turns off here rather than when the recording starts.
    private func updateMicrophonePreview() async {
        let preview = DevicePreview.microphone
        guard model.microphoneOn, bar?.isVisible == true else {
            preview.stop()
            return
        }
        await preview.start(deviceID: Preferences().microphoneDeviceID)
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            model.microphoneOn = false
        }
    }

    // MARK: Panels

    private func showSetup(placeCamera: Bool) async {
        CameraBubble.shared.showsHandle = true
        let frame = SetupFramePanel(screen: screen.frame, visible: screen.visibleFrame)
        frame.orderFrontRegardless()
        self.frame = frame
        for handle in RegionHandle.allCases {
            let panel = HandlePanel(handle: handle) { [weak self] delta in
                self?.drag(handle, by: delta)
            }
            panel.place(at: handle.anchor(in: region), within: handle == .move ? screen.visibleFrame : screen.frame)
            panel.orderFrontRegardless()
            handles[handle] = panel
        }
        let bar = SetupBarPanel(model: model, actions: .init(
            switchMode: { [weak self] mode in Task { await self?.switchMode(mode) } },
            toggleCamera: { [weak self] in Task { await self?.toggleCamera() } },
            toggleMicrophone: { [weak self] in Task { await self?.toggleMicrophone() } },
            toggleCursor: { [weak self] in self?.toggleCursor() },
            toggleSystemAudio: { [weak self] in self?.toggleSystemAudio() },
            setFrameRate: { [weak self] in self?.setFrameRate($0) },
            resizeCamera: { [weak self] step in
                if self?.model.cameraOn == true {
                    CameraBubble.shared.step(by: step)
                }
            },
            record: { [weak self] in self?.confirm() },
            cancel: { [weak self] in self?.cancel() }
        ))
        bar.onResize = { [weak self] in self?.updateGeometry() }
        self.bar = bar
        updateGeometry()
        bar.orderFrontRegardless()
        bar.makeKey()
        Task { await updateMicrophonePreview() }
        if placeCamera, model.cameraOn {
            await showCamera()
        }
    }

    /// A window recording captures only that window, so the bubble would never appear in it.
    private func showCamera() async {
        if model.windowID != nil {
            model.cameraOn = false
            CameraBubble.shared.hide()
            return
        }
        if !(await CameraBubble.shared.showFromPreferences(in: region)) {
            model.cameraOn = false
        }
    }

    private func drag(_ handle: RegionHandle, by delta: CGVector) {
        let adjusted = handle.adjust(region, by: delta, in: screen.frame, ratio: ratio)
        if handle == .move {
            CameraBubble.shared.move(by: CGVector(dx: adjusted.minX - region.minX, dy: adjusted.minY - region.minY))
        }
        region = adjusted
        CameraBubble.shared.setRegion(region)
        // A dragged screen or window frame is now a custom area.
        model.mode = .area
        model.windowID = nil
        model.pageInsets = nil
        updateGeometry()
    }

    private func updateGeometry() {
        for (handle, panel) in handles {
            panel.place(at: handle.anchor(in: region), within: handle == .move ? screen.visibleFrame : screen.frame)
        }
        bar?.place(below: region, on: screen)
        model.pixelSize = CGSize(width: Geometry.evenFloor(region.width * screen.backingScaleFactor), height: Geometry.evenFloor(region.height * screen.backingScaleFactor))
        model.frameLabel = RecordSetupFrame.label(pixels: model.pixelSize, ratio: ratio)
        let avoiding = [handles[.move]?.frame, bar?.frame].compactMap(\.self)
        frame?.update(region: region, label: model.frameLabel, avoiding: avoiding)
    }

    private func setSetupVisible(_ visible: Bool) {
        // The handle is for checking before recording, so the countdown and the recording show the bubble without it.
        CameraBubble.shared.showsHandle = visible
        for panel in [frame as NSWindow?, bar] + handles.values.map({ $0 as NSWindow? }) {
            if visible {
                panel?.orderFrontRegardless()
            } else {
                panel?.orderOut(nil)
            }
        }
        if visible {
            // Behind the camera bubble, which shares its level and stays up through a countdown.
            frame?.order(.below, relativeTo: 0)
            bar?.makeKey()
            Task { await updateMicrophonePreview() }
        } else {
            DevicePreview.microphone.stop()
        }
    }

    private func tearDownSetup() {
        setSetupVisible(false)
        frame = nil
        bar = nil
        handles.removeAll()
    }
}

// MARK: Handles

private final class HandlePanel: NSPanel {
    private let handle: RegionHandle

    init(handle: RegionHandle, onDrag: @escaping (CGVector) -> Void) {
        self.handle = handle
        let size = handle == .move ? NSSize(width: 56, height: 24) : NSSize(width: 20, height: 20)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = HandleView(handle: handle, onDrag: onDrag)
    }

    /// Centers the handle on `anchor`, kept fully on screen so edge handles of a full-screen region stay usable.
    func place(at anchor: CGPoint, within bounds: CGRect) {
        let size = frame.size
        var x = anchor.x - size.width / 2
        // The move grip floats just above the top edge, or just inside it when there is no room above.
        var y = handle == .move ? anchor.y + 14 : anchor.y - size.height / 2
        if handle == .move, y + size.height > bounds.maxY - 4 {
            y = anchor.y - size.height - 18
        }
        x = min(max(x, bounds.minX + 4), bounds.maxX - size.width - 4)
        y = min(max(y, bounds.minY + 4), bounds.maxY - size.height - 4)
        setFrameOrigin(CGPoint(x: x.rounded(), y: y.rounded()))
    }
}

private final class HandleView: NSView {
    private let handle: RegionHandle
    private let onDrag: (CGVector) -> Void
    private var last: CGPoint?
    private static let line = NSColor(Brutal.line)

    init(handle: RegionHandle, onDrag: @escaping (CGVector) -> Void) {
        self.handle = handle
        self.onDrag = onDrag
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        last = NSEvent.mouseLocation
        if handle == .move {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if let last {
            onDrag(CGVector(dx: point.x - last.x, dy: point.y - last.y))
        }
        last = point
    }

    override func mouseUp(with event: NSEvent) {
        last = nil
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    private var cursor: NSCursor {
        switch handle {
        case .move: .openHand
        case .topLeft: .frameResize(position: .topLeft, directions: .all)
        case .top: .frameResize(position: .top, directions: .all)
        case .topRight: .frameResize(position: .topRight, directions: .all)
        case .right: .frameResize(position: .right, directions: .all)
        case .bottomRight: .frameResize(position: .bottomRight, directions: .all)
        case .bottom: .frameResize(position: .bottom, directions: .all)
        case .bottomLeft: .frameResize(position: .bottomLeft, directions: .all)
        case .left: .frameResize(position: .left, directions: .all)
        }
    }

    /// The board's round handle, a 10 pt white circle with a 1.5 pt ink edge, in the middle of a 20 pt panel so it's easier
    /// to grab than it looks. The move grip, which the board doesn't draw, is a small dark pill with two rows of dots, in
    /// the size chip's colours.
    override func draw(_ dirtyRect: NSRect) {
        if handle == .move {
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 3), xRadius: (bounds.height - 6) / 2, yRadius: (bounds.height - 6) / 2)
            FloatingPanel.fillNS(SetupFrameChip.opacity, solid: FloatingPanel.solidNS).setFill()
            pill.fill()
            FloatingPanel.edgeNS(increased: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast).setStroke()
            pill.lineWidth = 1
            pill.stroke()
            NSColor.white.withAlphaComponent(0.85).setFill()
            for row in 0..<2 {
                for column in 0..<4 {
                    let dot = CGRect(x: bounds.midX - 11.5 + CGFloat(column) * 6.5, y: bounds.midY - 3.5 + CGFloat(row) * 5, width: 2.5, height: 2.5)
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
            return
        }
        let side = AreaHandles.diameter
        let circle = NSBezierPath(ovalIn: CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side))
        NSColor.white.setFill()
        circle.fill()
        Self.line.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()
    }
}

// MARK: Frame

/// The dim around the frame, its white and dark edges, and the size and ratio chip above it, across the screen the area is
/// on. The dim and edges are plain layer colours, so they cost no bitmap however large the screen. It ignores the mouse,
/// so the apps under it still take clicks while you set the recording up.
private final class SetupFramePanel: NSPanel {
    /// `rgba(12,12,16,0.46)`, from the board.
    private static let dimColor = CGColor(srgbRed: 12 / 255, green: 12 / 255, blue: 16 / 255, alpha: 0.46)
    private let screenFrame: CGRect
    /// Where the chip may go, in the panel's space: the screen less the menu bar and Dock, so it never covers either.
    private let chipBounds: CGRect
    private let dim = (0..<4).map { _ in CALayer() }
    private let innerEdge = CALayer()
    private let outerEdge = CALayer()
    private let chip = SetupFrameChip.Model()
    private let chipView: NSView
    private var region = CGRect.zero
    private var avoiding: [CGRect] = []

    init(screen: CGRect, visible: CGRect) {
        screenFrame = screen
        chipBounds = visible.offsetBy(dx: -screen.minX, dy: -screen.minY)
        chipView = NSView(hosting: SetupFrameChip(model: chip), movesWindow: false)
        super.init(contentRect: screen, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let content = NSView(frame: CGRect(origin: .zero, size: screen.size))
        content.wantsLayer = true
        for layer in dim {
            layer.backgroundColor = Self.dimColor
            content.layer?.addSublayer(layer)
        }
        // 1 pt white just outside the area, then 1 pt black at 35% outside that, as the area overlay draws it.
        innerEdge.borderColor = NSColor.white.withAlphaComponent(0.95).cgColor
        innerEdge.borderWidth = 1
        outerEdge.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
        outerEdge.borderWidth = 1
        content.layer?.addSublayer(outerEdge)
        content.layer?.addSublayer(innerEdge)
        content.addSubview(chipView)
        contentView = content
        setFrame(screen, display: false)
        chip.onSize = { [weak self] _ in self?.placeChip() }
    }

    /// `region` and `avoiding` are AppKit global rects; the chip keeps off `avoiding`, such as the bar and the move grip.
    func update(region: CGRect, label: String, avoiding: [CGRect]) {
        let origin = screenFrame.origin
        self.region = region.offsetBy(dx: -origin.x, dy: -origin.y)
        self.avoiding = avoiding.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rects = RecordSetupFrame.dimRects(around: self.region, in: CGRect(origin: .zero, size: screenFrame.size))
        for (index, layer) in dim.enumerated() {
            layer.isHidden = index >= rects.count
            if index < rects.count {
                layer.frame = rects[index]
            }
        }
        innerEdge.frame = self.region.insetBy(dx: -1, dy: -1)
        outerEdge.frame = self.region.insetBy(dx: -2, dy: -2)
        CATransaction.commit()
        chip.text = label
        placeChip()
    }

    private func placeChip() {
        let size = chip.size
        guard size.width > 0 else {
            return
        }
        chipView.frame = AreaLabelPlacement.frame(of: size, for: region, in: chipBounds, avoiding: avoiding).integral
    }
}

/// The frame's chip: the size in pixels and any ratio, in 12 pt bold SF Mono, white on the floating fill at 88%, as the
/// area overlay's chips are. Increase Contrast and Reduce Transparency make it solid.
private struct SetupFrameChip: View {
    @MainActor @Observable
    final class Model {
        var text = ""
        var size = CGSize.zero
        @ObservationIgnored var onSize: (CGSize) -> Void = { _ in }
    }

    static let opacity = 0.88
    let model: Model

    var body: some View {
        Text(verbatim: model.text)
            .font(.scaled(12, weight: .bold, design: .monospaced, tabular: true))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
            .floatingPanel(RoundedRectangle(cornerRadius: 8, style: .circular), opacity: Self.opacity)
            .fixedSize()
            // The panel sizes the chip's view from this, so the view never clips the chip or catches more than it.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                model.size = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
                model.onSize(model.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityHidden(true)
    }
}

// MARK: Setup bar

/// The dark bar under the frame (Record › Check before recording): what to record, the microphone with its level, the
/// camera, Mac sound and cursor toggles, the frame rate, Cancel, and Record as the one ink button. It grows to fit its
/// labels at the chosen text size and stays centred under the frame.
private final class SetupBarPanel: FloatingPanelWindow {
    struct Actions {
        let switchMode: @MainActor (CaptureTarget) -> Void
        let toggleCamera: @MainActor () -> Void
        let toggleMicrophone: @MainActor () -> Void
        let toggleCursor: @MainActor () -> Void
        let toggleSystemAudio: @MainActor () -> Void
        let setFrameRate: @MainActor (Int) -> Void
        /// Steps the camera bubble one size larger (1) or smaller (-1), from ⌘+ and ⌘−.
        let resizeCamera: @MainActor (Int) -> Void
        let record: @MainActor () -> Void
        let cancel: @MainActor () -> Void
    }

    /// From the frame's bottom edge to the bar.
    static let gap: CGFloat = 22
    private let actions: Actions
    private var region = CGRect.zero
    private var visibleFrame = CGRect.zero
    /// Called after the bar changes size, so the size chip can keep clear of it.
    var onResize: () -> Void = {}

    override var canBecomeKey: Bool { true }

    init(model: RecordingSetupModel, actions: Actions) {
        self.actions = actions
        super.init(contentRect: NSRect(origin: .zero, size: NSSize(width: 860, height: 52)))
        level = .statusBar
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSView(hosting: SetupBarView(model: model, preview: DevicePreview.microphone, actions: actions) { [weak self] size in
            self?.fit(size)
        })
        contentView?.layoutSubtreeIfNeeded()
    }

    override func cancelOperation(_ sender: Any?) {
        actions.cancel()
    }

    /// ⌘+ (or ⌘=) and ⌘− change the camera bubble's size, since its own panel never takes the keyboard.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command {
            switch event.charactersIgnoringModifiers {
            case "=", "+":
                actions.resizeCamera(1)
                return true
            case "-":
                actions.resizeCamera(-1)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    func place(below region: CGRect, on screen: NSScreen) {
        self.region = region
        visibleFrame = screen.visibleFrame
        setFrameOrigin(ControlPlacement.origin(for: frame.size, region: region, visible: visibleFrame, gap: Self.gap))
    }

    private func fit(_ size: CGSize) {
        let wanted = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted != frame.size, wanted.width > 0, wanted.height > 0 else {
            return
        }
        let origin = visibleFrame.isEmpty ? frame.origin : ControlPlacement.origin(for: wanted, region: region, visible: visibleFrame, gap: Self.gap)
        setFrame(NSRect(origin: origin, size: wanted), display: true)
        onResize()
    }
}

private struct SetupBarView: View {
    @Bindable var model: RecordingSetupModel
    let preview: DevicePreview
    let actions: SetupBarPanel.Actions
    let onSize: (CGSize) -> Void
    @Environment(\.textSize) private var textSize

    /// Buttons are 38 pt tall on the board: a toolbar button's 5 pt padding either side of this.
    static let toolbarContent: CGFloat = 28
    /// The same height for Cancel and Record, inside their 8 pt padding.
    static let buttonContent: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            BrutalSegmented(selection: Binding(get: { model.mode }, set: { actions.switchMode($0) }), options: CaptureTarget.allCases.map { ($0, $0.title) })
                .brutalTip("Switch what to record")
            FloatingDivider().padding(.horizontal, 4)
            microphone
            SetupToggle(on: model.cameraOn, title: "Camera", symbol: "video", offSymbol: "video.slash", help: cameraTip, detail: cameraDetail, action: actions.toggleCamera)
                .disabled(model.windowID != nil)
            SetupToggle(on: model.systemAudioOn, title: "Mac sound", symbol: "speaker.wave.2", offSymbol: "speaker.slash", help: "Record the sound other apps on your Mac play", action: actions.toggleSystemAudio)
            SetupToggle(on: model.cursorOn, title: "Cursor", symbol: "cursorarrow", offSymbol: "cursorarrow.slash", help: "Show the pointer in the recording", action: actions.toggleCursor)
            frameRate
            FloatingDivider().padding(.horizontal, 4)
            Button {
                actions.cancel()
            } label: {
                Text("Cancel").frame(minHeight: Self.buttonContent)
            }
            .buttonStyle(BrutalButtonStyle(floating: true))
            .keyboardShortcut(.cancelAction)
            .brutalTip("Cancel", key: "Esc")
            Button {
                actions.record()
            } label: {
                HStack(spacing: 8) {
                    RecordDot()
                    Text("Record")
                    Text(verbatim: "↩").font(.scaled(11)).opacity(0.6).accessibilityHidden(true)
                }
                .frame(minHeight: Self.buttonContent)
            }
            .buttonStyle(BrutalButtonStyle(.main, floating: true))
            .keyboardShortcut(.defaultAction)
            .brutalTip(recordTip, key: "↩")
            .accessibilityLabel(Text("Record"))
        }
        .padding(7)
        .fixedSize()
        .floatingPanel(RoundedRectangle(cornerRadius: 16, style: .circular))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Check before recording"))
        .accessibilityValue(Text(verbatim: model.frameLabel))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }

    private var microphone: some View {
        let on = model.microphoneOn
        return Button(action: actions.toggleMicrophone) {
            HStack(spacing: 8) {
                Image(systemName: on ? "mic" : "mic.slash")
                    .font(.scaled(13, weight: .semibold))
                    .frame(width: (16 * CGFloat(textSize.scale)).rounded())
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: model.microphoneName)
                        .font(Brutal.small)
                        .truncationMode(.tail)
                        .frame(maxWidth: (150 * CGFloat(textSize.scale)).rounded(), alignment: .leading)
                        .fixedSize()
                    MicLevelBars(meter: preview.meter, active: on && preview.isRunning)
                }
            }
            .foregroundStyle(SetupToggle.foreground(on: on))
            .frame(minHeight: Self.toolbarContent)
            .padding(.horizontal, 5)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, isOn: on, floating: true))
        .brutalTip(microphoneTip, detail: microphoneDetail)
        .accessibilityLabel(Text("Microphone"))
        .accessibilityValue((on ? Text("On") : Text("Off")) + Text(verbatim: ", \(model.microphoneName)"))
        .accessibilityAddTraits(.isToggle)
    }

    private var frameRate: some View {
        BrutalDropdown(title: "Frame rate", entries: model.frameRates.map { fps in
            .item("\(fps) fps", selected: fps == model.fps) { actions.setFrameRate(fps) }
        }) {
            HStack(spacing: 4) {
                Text("\(model.fps) fps")
                    .font(.scaled(12, weight: .bold, design: .monospaced, tabular: true))
                Image(systemName: "chevron.down")
                    .font(.scaled(9, weight: .bold))
                    .opacity(0.7)
            }
            .frame(minHeight: Self.toolbarContent)
            .padding(.horizontal, 3)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, floating: true))
        .brutalTip("Frame rate", detail: "Just for this recording. Settings › Recording sets the one each recording starts with.")
    }

    private var microphoneTip: LocalizedStringResource {
        if model.microphoneOn {
            return "Turn off the microphone"
        }
        return "Record your voice with the microphone"
    }

    private var microphoneDetail: LocalizedStringResource {
        "Settings › Recording picks which microphone."
    }

    private var cameraTip: LocalizedStringResource {
        if model.windowID != nil {
            return "A window recording has no camera bubble"
        }
        return model.cameraOn ? "Hide the camera bubble" : "Show your camera in a bubble"
    }

    private var cameraDetail: LocalizedStringResource? {
        guard model.cameraOn, model.windowID == nil else {
            return nil
        }
        return "Drag the bubble's handle, or press ⌘+ and ⌘−, to change its size."
    }

    private var recordTip: LocalizedStringResource {
        if model.countdownSeconds > 0 {
            return "Start recording after a \(model.countdownSeconds)-second countdown"
        }
        return "Start recording"
    }
}

/// A toggle on the setup bar: its symbol and name, on the 16% white fill while on. Off, the name is lighter and the
/// symbol is struck through, so on and off differ by more than the fill.
private struct SetupToggle: View {
    let on: Bool
    let title: LocalizedStringResource
    let symbol: String
    let offSymbol: String
    let help: LocalizedStringResource
    var detail: LocalizedStringResource?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    /// White while on, and 70% while off as on the board (90% with Increase Contrast). Disabled is left to the button style.
    static func foreground(on: Bool) -> some ShapeStyle {
        on ? AnyShapeStyle(Color.white) : AnyShapeStyle(ContrastAware(standard: .white.opacity(0.7), increased: .white.opacity(0.9)))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: on ? symbol : offSymbol)
                    .font(.scaled(13, weight: .semibold))
                    .frame(width: (16 * CGFloat(textSize.scale)).rounded())
                // The semibold name holds the button at its on width, so turning it on doesn't shift the bar.
                ZStack {
                    Text(title).font(Brutal.small).hidden()
                    Text(title).font(on ? Brutal.small : .scaled(12))
                }
            }
            .modifier(SetupToggleForeground(on: on, enabled: isEnabled))
            .frame(minHeight: SetupBarView.toolbarContent)
            .padding(.horizontal, 5)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, isOn: on, floating: true))
        .brutalTip(help, detail: detail)
        .accessibilityLabel(Text(title))
        .accessibilityValue(on ? Text("On") : Text("Off"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// Sets the toggle's colour unless it's disabled, when `BrutalButtonStyle`'s disabled colour shows through.
private struct SetupToggleForeground: ViewModifier {
    let on: Bool
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.foregroundStyle(SetupToggle.foreground(on: on))
        } else {
            content
        }
    }
}

/// Record's red dot with an ink ring, as on the board.
private struct RecordDot: View {
    @Environment(\.textSize) private var textSize

    var body: some View {
        let side = (13 * CGFloat(textSize.scale)).rounded()
        Circle()
            .fill(Brutal.record)
            .inkBorder(Circle(), width: 1.5, color: Color(hex: 0x16161A))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

// MARK: Countdown

/// The countdown a recording and a timed screenshot share (#1078): a dark floating panel with an accent ring that empties
/// as the seconds run out, the seconds in large tabular figures, and Cancel. `remaining` is read while the view draws, so
/// reading an observable property in it keeps the number current.
final class CountdownPanel: FloatingPanelWindow {
    /// What the countdown is for, which sets its hint and what VoiceOver says.
    enum Kind {
        case screenshot, recording
    }

    private let onCancel: () -> Void

    override var canBecomeKey: Bool { true }

    init(kind: Kind, total: Int, center: CGPoint, remaining: @escaping () -> Int?, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        let size = CountdownView.size(kind: kind, textSize: Preferences().textSize)
        let origin = CGPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded())
        super.init(contentRect: NSRect(origin: origin, size: size))
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSView(hosting: CountdownView(kind: kind, total: total, remaining: remaining, onCancel: onCancel))
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

private struct CountdownView: View {
    let kind: CountdownPanel.Kind
    let total: Int
    let remaining: () -> Int?
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize
    /// How full the ring is drawn, from 0 to 1.
    @State private var ring = 1.0

    static let width: CGFloat = 180
    static let ringSize: CGFloat = 92
    static let ringWidth: CGFloat = 6
    /// The ring's line runs 6 pt inside the 92 pt frame, so its circle is 80 pt across, as on the board.
    static let ringInset: CGFloat = 6
    static let top: CGFloat = 20
    static let bottom: CGFloat = 14
    static let spacing: CGFloat = 12
    static let digits = ScaledFont.scaled(40, weight: .bold, tabular: true)
    static let hintFont = ScaledFont.scaled(12)
    /// The Cancel button's text, as `BrutalButtonStyle` draws a floating secondary button.
    static let buttonFont = Brutal.body
    static let buttonPadding: CGFloat = 8

    static func hint(_ kind: CountdownPanel.Kind) -> String? {
        switch kind {
        case .screenshot: String(localized: "Open the menu you need")
        case .recording: nil
        }
    }

    /// The panel's size at `textSize`, worked out before it's shown so the window fits its shape.
    static func size(kind: CountdownPanel.Kind, textSize: TextSize) -> NSSize {
        func lineHeight(_ font: ScaledFont) -> CGFloat {
            NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: font.points(textSize))).rounded(.up)
        }
        let scale = CGFloat(textSize.scale)
        var height = top + (ringSize * scale).rounded() + spacing + lineHeight(buttonFont) + buttonPadding * 2 + bottom
        var width = (width * scale).rounded()
        if let hint = hint(kind) {
            height += lineHeight(hintFont) + spacing
            let font = NSFont.systemFont(ofSize: hintFont.points(textSize))
            width = max(width, (hint as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 32)
        }
        return NSSize(width: width, height: height)
    }

    private var seconds: Int { remaining() ?? 0 }

    private var label: String {
        switch kind {
        case .screenshot: String(localized: "Capturing in \(seconds) seconds")
        case .recording: String(localized: "Recording in \(seconds) seconds")
        }
    }

    var body: some View {
        let scale = CGFloat(textSize.scale)
        let ringSize = (Self.ringSize * scale).rounded()
        let ringWidth = Self.ringWidth * scale
        VStack(spacing: Self.spacing) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(contrast == .increased ? 0.4 : 0.14), lineWidth: ringWidth)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(Brutal.accent, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: "\(seconds)")
                    .font(Self.digits)
                    .foregroundStyle(.white)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(Motion.animation(.countdownFlip, reduceMotion: reduceMotion), value: seconds)
            }
            .padding(Self.ringInset * scale)
            .frame(width: ringSize, height: ringSize)
            .accessibilityHidden(true)
            if let hint = Self.hint(kind) {
                Text(hint)
                    .font(Self.hintFont)
                    .foregroundStyle(contrast == .increased ? Color.white : FloatingPanel.secondaryText)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            Button("Cancel · Esc") { onCancel() }
                .buttonStyle(BrutalButtonStyle(floating: true))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Text("Cancel"))
        }
        .padding(.top, Self.top)
        .padding(.bottom, Self.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .floatingPanel(RoundedRectangle(cornerRadius: 22, style: .circular))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
        .onChange(of: seconds, initial: true) { _, now in
            tick(now)
        }
    }

    /// Shows the seconds left on the ring, then drains it a second's worth while that second passes. Reduce Motion
    /// keeps the ring still at the seconds left. VoiceOver hears the whole label first, then each number.
    private func tick(_ now: Int) {
        guard now > 0 else { return }
        ring = CountdownRing.fraction(remaining: now, of: total)
        if let drain = Motion.animation(.countdownRing, reduceMotion: reduceMotion) {
            // Set in the next pass, so the drain starts from the seconds left rather than from wherever the last one was.
            Task { @MainActor in
                withAnimation(drain) { ring = CountdownRing.target(remaining: now, of: total) }
            }
        }
        let announcement = now == total ? label : "\(now)"
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}

/// Counts down on screen before a timed screenshot, so menus and hover states can be set up first. Shot isn't activated,
/// which would close a menu and end a hover; Esc works while the panel is key, and its Cancel button always does.
@MainActor
@Observable
final class ScreenshotCountdown {
    private var remaining: Int? {
        didSet { onTick(remaining) }
    }
    private var cancelled = false
    @ObservationIgnored private var panel: CountdownPanel?
    @ObservationIgnored private let onTick: (Int?) -> Void

    /// `onTick` gets the seconds left as the countdown runs, and `nil` when it ends.
    init(onTick: @escaping (Int?) -> Void) {
        self.onTick = onTick
    }

    /// Returns `true` once `seconds` have passed and the panel is gone, `false` if the user cancelled.
    func run(seconds: Int, on screen: NSScreen) async -> Bool {
        remaining = seconds
        // Bottom centre, clear of the menu bar and of whatever the user is about to open.
        let visible = screen.visibleFrame
        let panel = CountdownPanel(kind: .screenshot, total: seconds, center: CGPoint(x: visible.midX, y: visible.minY + 170), remaining: { [weak self] in self?.remaining }) { [weak self] in
            self?.cancelled = true
            self?.remaining = nil
            self?.panel?.orderOut(nil)
        }
        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        for second in stride(from: seconds, through: 1, by: -1) {
            remaining = second
            try? await Task.sleep(for: .seconds(1))
            if cancelled || Task.isCancelled {
                remaining = nil
                panel.orderOut(nil)
                return false
            }
        }
        remaining = nil
        panel.orderOut(nil)
        // Let the panel leave the screen before it's captured; it would otherwise be in the capture.
        try? await Task.sleep(for: .milliseconds(150))
        return !cancelled
    }
}
