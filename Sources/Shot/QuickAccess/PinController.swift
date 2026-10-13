import AppKit
import ShotCore
import SwiftUI

/// Floats captures above other windows as references. Each pin is its own panel: drag it anywhere, resize it from its
/// edges, and close it with its button or with Esc once you've clicked it.
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
            let loaded = await Task.detached { () -> (SendableImage, CGFloat)? in
                guard let data = try? Data(contentsOf: url), let image = ImageCodec.image(from: data) else {
                    return nil
                }
                return (SendableImage(image), ImageCodec.scale(of: data))
            }.value
            whenRead?()
            guard let self else {
                return
            }
            guard let (image, scale) = loaded else {
                Toast.error("Couldn't read \(url.lastPathComponent)")
                return
            }
            self.show(image.image, scale: scale, name: url.lastPathComponent, styled: styled)
        }
    }

    private func show(_ image: CGImage, scale: CGFloat, name: String, styled: Bool) {
        let size = CGSize(width: CGFloat(image.width) / max(scale, 1), height: CGFloat(image.height) / max(scale, 1))
        let screen = NSScreen.underPointer ?? NSScreen.screens[0]
        let frame = PinLayout.initialFrame(for: size, in: screen.visibleFrame, index: panels.count)
        let panel = PinPanel(frame: frame, aspect: size)
        // The window's shadow would trace the image's own, transparent margin and all.
        panel.hasShadow = !styled
        panel.contentView = NSView(hosting: PinView(image: NSImage(cgImage: image, size: size), name: name, styled: styled) { [weak panel] in
            panel?.close()
        })
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

private final class PinPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    init(frame: CGRect, aspect: CGSize) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = aspect
        let shorter = min(aspect.width, aspect.height)
        if shorter > 0 {
            contentMinSize = CGSize(width: aspect.width * 48 / shorter, height: aspect.height * 48 / shorter)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }
}

private struct PinView: View {
    let image: NSImage
    let name: String
    let styled: Bool
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Pinned \(name)"))
            WindowDragArea()
            if hovering {
                CornerButton(symbol: "xmark", help: "Close") { close() }
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .modifier(PinFrame(styled: styled))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = inside
            }
        }
        .environment(\.colorScheme, .light)
    }
}

/// A plain capture sits on black in an ink frame. A styled one is left clear, so its transparent margin, shadow and
/// border show as Copy has them.
private struct PinFrame: ViewModifier {
    let styled: Bool

    func body(content: Content) -> some View {
        if styled {
            content
        } else {
            content
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular))
                .inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular), width: 2)
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
