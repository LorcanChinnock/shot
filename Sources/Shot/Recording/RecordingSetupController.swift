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
    }

    var options: Recorder.Options { .init(camera: cameraOn, microphone: microphoneOn, showsCursor: cursorOn, windowID: windowID, pageInsets: pageInsets) }
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
    private var frame: RecordingBorderPanel?
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

    func toggleMicrophone() {
        model.microphoneOn.toggle()
    }

    func toggleCursor() {
        model.cursorOn.toggle()
    }

    // MARK: Panels

    private func showSetup(placeCamera: Bool) async {
        let frame = RecordingBorderPanel(region: region, style: .setup)
        frame.orderFrontRegardless()
        self.frame = frame
        for handle in RegionHandle.allCases {
            let panel = HandlePanel(handle: handle) { [weak self] delta in
                self?.drag(handle, by: delta)
            }
            panel.place(at: handle.anchor(in: region), within: screen.frame)
            panel.orderFrontRegardless()
            handles[handle] = panel
        }
        let bar = SetupBarPanel(model: model, actions: .init(
            switchMode: { [weak self] mode in Task { await self?.switchMode(mode) } },
            toggleCamera: { [weak self] in Task { await self?.toggleCamera() } },
            toggleMicrophone: { [weak self] in self?.toggleMicrophone() },
            toggleCursor: { [weak self] in self?.toggleCursor() },
            record: { [weak self] in self?.confirm() },
            cancel: { [weak self] in self?.cancel() }
        ))
        self.bar = bar
        updateGeometry()
        bar.orderFrontRegardless()
        bar.makeKey()
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
        frame?.setRegion(region)
        for (handle, panel) in handles {
            panel.place(at: handle.anchor(in: region), within: screen.frame)
        }
        bar?.place(below: region, on: screen)
        model.pixelSize = CGSize(width: Geometry.evenFloor(region.width * screen.backingScaleFactor), height: Geometry.evenFloor(region.height * screen.backingScaleFactor))
    }

    private func setSetupVisible(_ visible: Bool) {
        for panel in [frame as NSWindow?, bar] + handles.values.map({ $0 as NSWindow? }) {
            if visible {
                panel?.orderFrontRegardless()
            } else {
                panel?.orderOut(nil)
            }
        }
        if visible {
            bar?.makeKey()
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

    override func draw(_ dirtyRect: NSRect) {
        // Square knob with a hard shadow; leaves 2 pt on the right and bottom for the shadow.
        let body = CGRect(x: 0, y: 2, width: bounds.width - 2, height: bounds.height - 2)
        let radius: CGFloat = handle == .move ? 8 : 4
        Self.line.setFill()
        // Starts under the border stroke so no background shows between knob and shadow.
        NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1).offsetBy(dx: 2, dy: -2), xRadius: radius, yRadius: radius).fill()
        NSColor(Brutal.paper).setFill()
        let shape = NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        shape.fill()
        Self.line.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        if handle == .move {
            NSColor(Brutal.ink).setFill()
            for row in 0..<2 {
                for column in 0..<4 {
                    let dot = CGRect(x: body.midX - 13 + CGFloat(column) * 8, y: body.midY - 4 + CGFloat(row) * 6, width: 3, height: 3)
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
        }
    }
}

// MARK: Setup bar

private final class SetupBarPanel: FloatingPanelWindow {
    struct Actions {
        let switchMode: @MainActor (CaptureTarget) -> Void
        let toggleCamera: @MainActor () -> Void
        let toggleMicrophone: @MainActor () -> Void
        let toggleCursor: @MainActor () -> Void
        let record: @MainActor () -> Void
        let cancel: @MainActor () -> Void
    }

    static let size = NSSize(width: 656, height: 60)

    override var canBecomeKey: Bool { true }

    init(model: RecordingSetupModel, actions: Actions) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size))
        level = .statusBar
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSView(hosting: SetupBarView(model: model, actions: actions))
    }

    func place(below region: CGRect, on screen: NSScreen) {
        setFrameOrigin(ControlPlacement.origin(for: Self.size, region: region, visible: screen.visibleFrame, gap: 22))
    }
}

private struct SetupBarView: View {
    @Bindable var model: RecordingSetupModel
    let actions: SetupBarPanel.Actions

    var body: some View {
        HStack(spacing: 10) {
            BrutalSegmented(selection: Binding(get: { model.mode }, set: { actions.switchMode($0) }), options: CaptureTarget.allCases.map { ($0, $0.title) })
                .brutalTip("Switch what to record")
            BrutalBadge(text: "\(Int(model.pixelSize.width)) × \(Int(model.pixelSize.height))")
                .fixedSize()
            FloatingDivider()
            OptionToggle(on: model.cameraOn, symbol: model.cameraOn ? "video.fill" : "video.slash.fill", help: model.cameraOn ? "Hide camera bubble" : "Show camera bubble", action: actions.toggleCamera)
            OptionToggle(on: model.microphoneOn, symbol: model.microphoneOn ? "mic.fill" : "mic.slash.fill", help: model.microphoneOn ? "Turn off microphone" : "Turn on microphone", action: actions.toggleMicrophone)
            OptionToggle(on: model.cursorOn, symbol: model.cursorOn ? "cursorarrow" : "cursorarrow.slash", help: model.cursorOn ? "Hide cursor" : "Show cursor", action: actions.toggleCursor)
            Spacer(minLength: 0)
            Button {
                actions.cancel()
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 16, height: 16)
            }
            .buttonStyle(BrutalButtonStyle(.toolbar, floating: true))
            .keyboardShortcut(.cancelAction)
            .brutalTip("Cancel (Esc)")
            .accessibilityLabel(Text("Cancel"))
            Button {
                actions.record()
            } label: {
                Label("Record", systemImage: "record.circle.fill").labelStyle(.titleAndIcon).fixedSize()
            }
            .buttonStyle(BrutalButtonStyle(.main, floating: true))
            .keyboardShortcut(.defaultAction)
            .brutalTip(model.countdownSeconds > 0 ? "Start recording after a \(model.countdownSeconds)-second countdown (Return)" : "Start recording (Return)")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .floatingPanel(RoundedRectangle(cornerRadius: 16, style: .circular))
    }
}

private struct OptionToggle: View {
    let on: Bool
    let symbol: String
    let help: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 16, height: 16)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar, isOn: on, floating: true))
        .brutalTip(help)
        .accessibilityLabel(Text(help))
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
