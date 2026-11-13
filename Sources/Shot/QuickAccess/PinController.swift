import AppKit
import ShotCore
import SwiftUI

/// Floats captures above other windows as references. Each pin is its own panel: drag it anywhere, resize it from its
/// edges, and close it with its bar's button or with Esc once you've clicked it. The bar also sets how see-through the
/// pin is and lets clicks pass through it to the window underneath.
@MainActor
final class PinController {
    static let shared = PinController()

    private var panels: [PinPanel] = []

    /// Pins the image at `url`, read off the main actor. `whenRead` runs once the file has been read, or failed to be,
    /// so a caller can delete a temporary file only after the pin no longer needs it. A `styled` image already has its
    /// own shadow, border and corners on a transparent margin, so it floats as it is, with no frame of the pin's own.
    func pin(_ url: URL, styled: Bool = false, whenRead: (@MainActor () -> Void)? = nil) {
        Task { [weak self] in
            // Decoded now, from the file's bytes: an image read lazily from `url` decodes when it's first drawn, after
            // `whenRead` may have deleted the file, and draws black.
            let loaded = await Task.detached { () -> (SendableImage, CGFloat, Bool)? in
                guard let data = try? Data(contentsOf: url), let image = ImageCodec.image(from: data) else {
                    return nil
                }
                // A window captured with its shadow, or with round corners, is see-through at its edges. It floats as
                // it is too, rather than on a frame that would show its transparent margin.
                return (SendableImage(image), ImageCodec.scale(of: data), styled || image.hasTransparentPixels)
            }.value
            whenRead?()
            guard let self else {
                return
            }
            guard let (image, scale, frameless) = loaded else {
                Toast.error("Couldn't read \(url.lastPathComponent)")
                return
            }
            self.show(image.image, scale: scale, name: url.lastPathComponent, frameless: frameless)
        }
    }

    private func show(_ image: CGImage, scale: CGFloat, name: String, frameless: Bool) {
        let size = CGSize(width: CGFloat(image.width) / max(scale, 1), height: CGFloat(image.height) / max(scale, 1))
        let screen = NSScreen.underPointer ?? NSScreen.screens[0]
        let frame = PinLayout.initialFrame(for: size, in: screen.visibleFrame, index: panels.count)
        let panel = PinPanel(frame: frame, aspect: size)
        // The window's shadow would trace the image's own, transparent margin and all.
        panel.hasShadow = !frameless
        panel.contentView = NSView(hosting: PinView(image: NSImage(cgImage: image, size: size), name: name, frameless: frameless, state: panel.state))
        // Let go of the panel on the next turn, not while it's still inside its own close().
        panel.onClose = { [weak self] in
            Task { @MainActor in
                self?.panels.removeAll { !$0.isVisible }
            }
        }
        panels.append(panel)
        // Not made key, so pinning never takes typing away from the app in front; clicking the pin focuses it for Esc.
        panel.orderFrontRegardless()
    }
}

/// What a pin's bar and image show, shared by the panel and its SwiftUI content.
@MainActor
@Observable
final class PinState {
    var opacity = PinOpacity.full
    var clickThrough = false
    /// The pointer is over the pin, as SwiftUI sees it while the pin takes clicks.
    var hovering = false
    /// The pointer is over the pin, as the panel's event monitor sees it while clicks pass through.
    var pointerInside = false
    /// The pin is focused, after a click, so the keyboard reaches its bar.
    var isKey = false
    var barHeight: CGFloat = 0

    @ObservationIgnored var close: () -> Void = {}
    @ObservationIgnored var changed: () -> Void = {}

    /// The bar starts hidden, and shows while the pointer is over the pin or the pin is focused.
    var showsBar: Bool { clickThrough ? pointerInside : hovering || isKey }

    func setOpacity(_ value: Double) {
        opacity = PinOpacity.clamped(value)
        changed()
    }

    func toggleClickThrough() {
        clickThrough.toggle()
        changed()
    }
}

private final class PinPanel: FloatingPanelWindow {
    let state = PinState()
    var onClose: (() -> Void)?
    /// Watch the pointer while clicks pass through, since the panel then gets no mouse events of its own.
    private var monitors: [Any] = []

    override var canBecomeKey: Bool { true }

    init(frame: CGRect, aspect: CGSize) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable])
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = aspect
        let shorter = min(aspect.width, aspect.height)
        if shorter > 0 {
            contentMinSize = CGSize(width: aspect.width * 48 / shorter, height: aspect.height * 48 / shorter)
        }
        state.close = { [weak self] in self?.close() }
        state.changed = { [weak self] in self?.stateChanged() }
    }

    override func becomeKey() {
        super.becomeKey()
        state.isKey = true
    }

    override func resignKey() {
        super.resignKey()
        state.isKey = false
    }

    /// Focuses the pin before a click is handled, so the first click on the slider moves it rather than only focusing.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// ↑ and ↓ make the pin more or less see-through, once it's focused.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: state.setOpacity(PinOpacity.stepped(state.opacity, up: true))
        case 125: state.setOpacity(PinOpacity.stepped(state.opacity, up: false))
        default: super.keyDown(with: event)
        }
    }

    override func close() {
        stopWatchingPointer()
        super.close()
        onClose?()
        onClose = nil
    }

    private func stateChanged() {
        // The system shadow follows the drawn alpha, which the opacity changes.
        refreshShadow()
        if state.clickThrough {
            watchPointer()
        } else {
            stopWatchingPointer()
            ignoresMouseEvents = false
        }
    }

    /// While clicks pass through, the bar's strip still takes them, so its buttons can turn click-through off again.
    private func watchPointer() {
        updatePointer()
        guard monitors.isEmpty else {
            return
        }
        // Both run on the main thread: the global one for moves over other apps, the local one for moves over Shot's own.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func stopWatchingPointer() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        state.pointerInside = false
    }

    private func updatePointer() {
        let pointer = NSEvent.mouseLocation
        let inside = frame.contains(pointer)
        if state.pointerInside != inside {
            withAnimation(Motion.reduced ? nil : Motion.fade) {
                state.pointerInside = inside
            }
        }
        let inBar = inside && PinLayout.barStrip(in: frame, barHeight: state.barHeight).contains(pointer)
        if ignoresMouseEvents == inBar {
            ignoresMouseEvents = !inBar
        }
    }
}

private struct PinView: View {
    let image: NSImage
    let name: String
    let frameless: Bool
    let state: PinState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(state.opacity)
                .accessibilityLabel(Text("Pinned \(name)"))
                .accessibilityValue(Text("\(PinOpacity.percent(state.opacity)) percent opacity"))
                // The bar is hidden until the pointer is over the pin, so VoiceOver reaches its controls from the image.
                .accessibilityAdjustableAction { direction in
                    state.setOpacity(PinOpacity.stepped(state.opacity, up: direction == .increment))
                }
                .accessibilityAction(named: Text("Close")) { state.close() }
                .accessibilityAction(named: state.clickThrough ? Text("Stop Clicking Through") : Text("Click Through")) {
                    state.toggleClickThrough()
                }
            WindowDragArea()
            if state.showsBar {
                PinBar(state: state)
                    .padding(PinLayout.barInset)
                    .transition(.opacity)
            }
        }
        .modifier(PinFrame(frameless: frameless))
        .onHover { inside in
            withAnimation(reduceMotion ? nil : Motion.fade) {
                state.hovering = inside
            }
        }
        .animation(reduceMotion ? nil : Motion.fade, value: state.isKey)
    }
}

/// The dark bar across the top of a pin: Close, how see-through it is, its slider, and Click Through. A narrow pin drops
/// the label, then the slider, so the two buttons always fit.
private struct PinBar: View {
    let state: PinState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(label: true, slider: true)
            row(label: false, slider: true)
            row(label: false, slider: false)
        }
        .padding(3)
        .floatingPanel(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular), opacity: FloatingPanel.Opacity.pinBar)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.barHeight = $0 }
    }

    private func row(label: Bool, slider: Bool) -> some View {
        HStack(spacing: 4) {
            Button { state.close() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(ThemeButtonStyle(.toolbar, floating: true))
            .themeTip("Close")
            .accessibilityLabel(Text("Close"))
            if label {
                Text("Pinned · \(PinOpacity.percent(state.opacity))%")
                    .font(.scaled(10.5, tabular: true))
                    .foregroundStyle(FloatingPanel.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            if slider {
                ThemeSlider(
                    value: Binding(get: { state.opacity }, set: { state.setOpacity($0) }),
                    range: PinOpacity.range,
                    width: 60,
                    floating: true,
                    defaultValue: PinOpacity.full
                )
                .accessibilityLabel(Text("Opacity"))
                .padding(.horizontal, 4)
            }
            Button { state.toggleClickThrough() } label: {
                Image(systemName: "cursorarrow").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(ThemeButtonStyle(.toolbar, isOn: state.clickThrough, floating: true))
            .themeTip(clickThroughTip)
            .accessibilityLabel(Text("Click Through"))
        }
    }

    /// A computed property, so both titles reach the strings catalog.
    private var clickThroughTip: LocalizedStringResource {
        state.clickThrough ? "Stop Clicking Through" : "Click Through"
    }
}

/// A plain capture sits on a group-cornered frame with a faint ink edge, as on the board. A see-through one, such as a
/// styled capture or a window with its shadow, is left clear, so its transparent margin shows as it is.
private struct PinFrame: ViewModifier {
    let frameless: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if frameless {
            content
        } else {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
            content
                .clipShape(shape)
                .inkBorder(shape, width: 1, color: Color(hex: 0x16161A).opacity(contrast == .increased ? 0.6 : 0.18))
        }
    }
}

/// Moves the window from anywhere on the image, since a hosting view doesn't move its window by its background.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
