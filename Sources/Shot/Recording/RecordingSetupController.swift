import AppKit
import AVFoundation
import Observation
import os
import ShotCore
import SwiftUI

private let log = Logger.shot("recording")

enum RecordingMode: String, CaseIterable {
    case area, screen, window

    var title: String { rawValue.capitalized }
}

@MainActor
@Observable
final class RecordingSetupModel {
    var mode: RecordingMode
    var pixelSize: CGSize = .zero
    var cameraOn: Bool
    var microphoneOn: Bool
    var cursorOn: Bool
    var countdown: Int?

    init(mode: RecordingMode, prefs: Preferences) {
        self.mode = mode
        cameraOn = prefs.recordCamera
        microphoneOn = prefs.recordMicrophone
        cursorOn = prefs.recordShowsCursor
    }
}

/// Lets the user frame the recording, set options and press Record; recording starts after a 3-second countdown.
@MainActor
final class RecordingSetupController {
    /// Only crosses the continuation on the main actor.
    enum Result: @unchecked Sendable {
        case start(screen: NSScreen, region: CGRect)
        case cancel
    }

    static let countdownSeconds = 3

    private let model: RecordingSetupModel
    private var screen: NSScreen
    private var region: CGRect
    private var frame: RecordingBorderPanel?
    private var handles: [RegionHandle: HandlePanel] = [:]
    private var bar: SetupBarPanel?
    private var countdownPanel: CountdownPanel?
    private var countdownTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<Result, Never>?

    init(mode: RecordingMode, screen: NSScreen, region: CGRect) {
        model = RecordingSetupModel(mode: mode, prefs: Preferences())
        self.screen = screen
        self.region = region
    }

    /// Lets the user pick an area or window with the live overlay, or takes the screen under the pointer.
    static func pickRegion(mode: RecordingMode) async -> (NSScreen, CGRect)? {
        let screens = NSScreen.screens
        if mode == .screen {
            let screen = NSScreen.underPointer ?? screens[0]
            return (screen, screen.fullCaptureFrame)
        }
        let displays = screens.map { OverlayDisplay(frame: $0.frame, scale: $0.backingScaleFactor, image: nil) }
        let windows = SelectionOverlayController.onScreenWindows()
        guard let selection = await SelectionOverlayController.select(displays: displays, windowMode: mode == .window, windows: windows, isLive: true) else {
            return nil
        }
        switch selection {
        case let .area(index, rect):
            let screen = screens[index]
            return (screen, rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY))
        case let .window(info):
            let frame = Geometry.flip(info.frame, primaryHeight: screens.first?.frame.height ?? 0)
            let screen = screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) } ?? screens[0]
            return (screen, frame.intersection(screen.frame))
        case let .fullDisplay(index):
            return (screens[index], screens[index].fullCaptureFrame)
        }
    }

    func run() async -> Result {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { await self.showSetup(placeCamera: true) }
        }
    }

    // MARK: Actions

    /// Starts the countdown; the record hotkey and Return also call this.
    func confirm() {
        guard model.countdown == nil, continuation != nil else {
            return
        }
        setSetupVisible(false)
        model.countdown = Self.countdownSeconds
        let panel = CountdownPanel(center: CGPoint(x: region.midX, y: region.midY), model: model) { [weak self] in
            self?.cancelCountdown()
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        countdownPanel = panel
        countdownTask = Task {
            for remaining in stride(from: Self.countdownSeconds, through: 1, by: -1) {
                model.countdown = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    return
                }
            }
            finish(.start(screen: screen, region: region))
        }
    }

    func cancel() {
        CameraBubble.shared.hide()
        finish(.cancel)
    }

    private func cancelCountdown() {
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

    func switchMode(_ mode: RecordingMode) async {
        guard model.countdown == nil else {
            return
        }
        setSetupVisible(false)
        if let picked = await Self.pickRegion(mode: mode) {
            model.mode = mode
            screen = picked.0
            region = picked.1
            tearDownSetup()
            await showSetup(placeCamera: true)
        } else {
            setSetupVisible(true)
        }
    }

    func toggleCamera() async {
        model.cameraOn.toggle()
        UserDefaults.standard.set(model.cameraOn, forKey: PreferenceKey.recordCamera)
        if model.cameraOn {
            await showCamera()
        } else {
            CameraBubble.shared.hide()
        }
    }

    func toggleMicrophone() {
        model.microphoneOn.toggle()
        UserDefaults.standard.set(model.microphoneOn, forKey: PreferenceKey.recordMicrophone)
    }

    func toggleCursor() {
        model.cursorOn.toggle()
        UserDefaults.standard.set(model.cursorOn, forKey: PreferenceKey.recordShowsCursor)
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
        NSApp.activate()
        bar.orderFrontRegardless()
        bar.makeKey()
        if placeCamera, model.cameraOn {
            await showCamera()
        }
    }

    private func showCamera() async {
        if !(await CameraBubble.shared.showFromPreferences(in: region)) {
            model.cameraOn = false
        }
    }

    private func drag(_ handle: RegionHandle, by delta: CGVector) {
        let adjusted = handle.adjust(region, by: delta, in: screen.frame)
        if handle == .move {
            CameraBubble.shared.move(by: CGVector(dx: adjusted.minX - region.minX, dy: adjusted.minY - region.minY))
        }
        region = adjusted
        // A dragged screen or window frame is now a custom area.
        model.mode = .area
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
    private static let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)

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
        Self.ink.setFill()
        // Starts under the border stroke so no background shows between knob and shadow.
        NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1).offsetBy(dx: 2, dy: -2), xRadius: radius, yRadius: radius).fill()
        NSColor.white.setFill()
        let shape = NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        shape.fill()
        Self.ink.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        if handle == .move {
            Self.ink.setFill()
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

private final class SetupBarPanel: NSPanel {
    struct Actions {
        let switchMode: @MainActor (RecordingMode) -> Void
        let toggleCamera: @MainActor () -> Void
        let toggleMicrophone: @MainActor () -> Void
        let toggleCursor: @MainActor () -> Void
        let record: @MainActor () -> Void
        let cancel: @MainActor () -> Void
    }

    static let size = NSSize(width: 620, height: 66)

    override var canBecomeKey: Bool { true }

    init(model: RecordingSetupModel, actions: Actions) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
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
            BrutalSegmented(selection: Binding(get: { model.mode }, set: { actions.switchMode($0) }), options: RecordingMode.allCases.map { ($0, $0.title) }, color: Brutal.sky)
                .brutalTip("Switch what to record")
            BrutalChip(text: "\(Int(model.pixelSize.width)) × \(Int(model.pixelSize.height))")
                .fixedSize()
            Rectangle().fill(Brutal.ink.opacity(0.2)).frame(width: 2, height: 28)
            OptionToggle(on: model.cameraOn, symbol: model.cameraOn ? "video.fill" : "video.slash.fill", help: model.cameraOn ? "Camera bubble on" : "Camera bubble off", action: actions.toggleCamera)
            OptionToggle(on: model.microphoneOn, symbol: model.microphoneOn ? "mic.fill" : "mic.slash.fill", help: model.microphoneOn ? "Microphone on" : "Microphone off", action: actions.toggleMicrophone)
            OptionToggle(on: model.cursorOn, symbol: model.cursorOn ? "cursorarrow" : "cursorarrow.slash", help: model.cursorOn ? "Cursor shown" : "Cursor hidden", action: actions.toggleCursor)
            Spacer(minLength: 0)
            Button {
                actions.cancel()
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 16, height: 16)
            }
            .buttonStyle(BrutalButtonStyle(compact: true))
            .keyboardShortcut(.cancelAction)
            .brutalTip("Cancel (Esc)")
            .accessibilityLabel(Text("Cancel"))
            Button {
                actions.record()
            } label: {
                Label("Record", systemImage: "record.circle.fill").labelStyle(.titleAndIcon).fixedSize()
            }
            .buttonStyle(BrutalButtonStyle(color: Brutal.red, compact: true))
            .keyboardShortcut(.defaultAction)
            .brutalTip("Start recording after a 3-second countdown (Return)")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .brutalSurface(Color.white.opacity(0.72), glass: true, radius: 14, shadow: 4)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .environment(\.colorScheme, .light)
    }
}

private struct OptionToggle: View {
    let on: Bool
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 16, height: 16)
        }
        .buttonStyle(BrutalButtonStyle(color: on ? Brutal.mint : .white, compact: true))
        .brutalTip(help)
        .accessibilityLabel(Text(help))
    }
}

// MARK: Countdown

private final class CountdownPanel: NSPanel {
    private static let size = NSSize(width: 220, height: 250)
    private let onCancel: () -> Void

    override var canBecomeKey: Bool { true }

    init(center: CGPoint, model: RecordingSetupModel, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        let origin = CGPoint(x: center.x - Self.size.width / 2, y: center.y - Self.size.height / 2)
        super.init(contentRect: NSRect(origin: origin, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSView(hosting: CountdownView(model: model, onCancel: onCancel))
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

private struct CountdownView: View {
    let model: RecordingSetupModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("\(model.countdown ?? 0)")
                .font(.system(size: 84, weight: .black, design: .rounded))
                .foregroundStyle(Brutal.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: model.countdown)
                .frame(width: 148, height: 148)
                .brutalCircle(Brutal.yellow, shadow: 6)
            Button("Cancel") { onCancel() }
                .buttonStyle(BrutalButtonStyle(compact: true))
                .keyboardShortcut(.cancelAction)
        }
        // Fill the panel so the hosting view can't shrink it and clip the shadows.
        .padding(.trailing, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .light)
    }
}
