import AppKit
import ShotCore

/// Drags a Quick Access card's file into another app. AppKit starts the drag rather than SwiftUI's `onDrag`, since only
/// an `NSDraggingSource` hears how the drag ended: a card dropped somewhere closes, shrinking away, and one let go
/// nowhere comes back. The picture under the pointer is the card lifted, a little bigger with a deeper shadow.
@MainActor
final class QuickAccessDrag: NSObject, NSDraggingSource {
    /// How far the pointer moves with the button down before it's a drag rather than a click.
    private static let threshold: CGFloat = 4
    /// How much bigger the lifted card is than the card.
    static let lift: CGFloat = 1.03
    /// Room round the lifted card for its shadow.
    private static let shadowMargin: CGFloat = 24

    private weak var controller: QuickAccessController?
    private var monitor: Any?
    /// The card pressed and where, until the button goes up or the drag starts.
    private var pressed: (id: UUID, point: CGPoint)?
    /// The card being dragged.
    private var dragging: UUID?

    init(controller: QuickAccessController) {
        self.controller = controller
    }

    /// Watches presses in `panel` for a drag starting on a card.
    func watch(_ panel: NSWindow) {
        guard monitor == nil else {
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self, weak panel] event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated {
                guard let self, let panel, event.window === panel else {
                    return false
                }
                return self.consumes(event, in: panel)
            }
            return consumed ? nil : event
        }
    }

    /// Whether `event` starts a drag, which then has the pointer, so nothing under it should see the event.
    private func consumes(_ event: NSEvent, in panel: NSWindow) -> Bool {
        switch event.type {
        case .leftMouseDown:
            pressed = controller?.card(at: event.locationInWindow).map { ($0, event.locationInWindow) }
            return false
        case .leftMouseDragged:
            guard dragging == nil, let pressed, let controller, let view = panel.contentView else {
                return false
            }
            let moved = hypot(event.locationInWindow.x - pressed.point.x, event.locationInWindow.y - pressed.point.y)
            guard moved >= Self.threshold, let card = controller.card(withID: pressed.id), let frame = controller.windowFrame(of: pressed.id) else {
                return false
            }
            self.pressed = nil
            let item = NSDraggingItem(pasteboardWriter: (card.styledURL ?? card.fileURL) as NSURL)
            let margin = Self.shadowMargin
            let lifted = frame.insetBy(dx: -frame.width * (Self.lift - 1) / 2 - margin, dy: -frame.height * (Self.lift - 1) / 2 - margin)
            item.setDraggingFrame(view.convert(lifted, from: nil), contents: Self.liftedImage(card.thumbnail, size: lifted.size, margin: margin))
            dragging = card.id
            view.beginDraggingSession(with: [item], event: event, source: self)
            controller.dragBegan(card.id)
            return true
        case .leftMouseUp:
            pressed = nil
            return false
        default:
            return false
        }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            guard let id = dragging else {
                return
            }
            dragging = nil
            controller?.dragEnded(id, dropped: operation != [])
        }
    }

    /// The card as it's carried: the capture filling a rounded card `lift` times its size, on a soft, deep shadow, in the
    /// middle of `size` with `margin` all round for the shadow.
    private static func liftedImage(_ thumbnail: NSImage, size: CGSize, margin: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { bounds in
            let card = bounds.insetBy(dx: margin, dy: margin)
            let path = NSBezierPath(roundedRect: card, xRadius: Theme.Radius.panel, yRadius: Theme.Radius.panel)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            path.addClip()
            // Fills the card from its middle, as the card shows it.
            let picture = thumbnail.size
            if thumbnail.isTemplate {
                // A recording with no first frame: its film symbol, small in the middle, as on the card.
                thumbnail.draw(in: CGRect(x: card.midX - 20, y: card.midY - 20, width: 40, height: 40))
            } else if picture.width > 0, picture.height > 0 {
                let scale = max(card.width / picture.width, card.height / picture.height)
                let drawn = CGSize(width: picture.width * scale, height: picture.height * scale)
                thumbnail.draw(in: CGRect(x: card.midX - drawn.width / 2, y: card.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
            }
            NSColor.black.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}
