import CoreGraphics
import Foundation

/// The label in the middle of a highlighted window, page or screen (Capture › Window pick and delay): a camera disc, then a
/// panel with the name and size, then a hint. Rects are in the overlay's view space, with y going up, as AppKit draws it.
public enum WindowPickLabel {
    public enum Part: Sendable, Equatable {
        case icon
        case name
        case hint
    }

    /// The least room kept between the label and the edges of what's highlighted, before parts are dropped.
    public static let inset: CGFloat = 12
    /// The least room kept between the label and the screen's edge.
    public static let margin: CGFloat = 8
    /// From anything the label keeps off, such as the capture bar, to the label.
    public static let clearance: CGFloat = 12

    /// Where each part goes, top to bottom, `spacing` apart. All three show when they fit inside `target`, else the name and
    /// hint, else the name alone. The stack is centred on the part of `target` that's on screen, kept inside `bounds`, and
    /// moved above or below anything in `avoiding` that it would cover.
    public static func layout(
        icon: CGSize, name: CGSize, hint: CGSize, spacing: CGFloat, target: CGRect, in bounds: CGRect, avoiding: [CGRect] = []
    ) -> [(part: Part, frame: CGRect)] {
        let visible = target.intersection(bounds)
        let room = visible.isNull ? .zero : visible.insetBy(dx: inset, dy: inset).standardized
        let options: [[(Part, CGSize)]] = [[(.icon, icon), (.name, name), (.hint, hint)], [(.name, name), (.hint, hint)], [(.name, name)]]
        func size(of parts: [(Part, CGSize)]) -> CGSize {
            CGSize(
                width: parts.map(\.1.width).max() ?? 0,
                height: parts.map(\.1.height).reduce(0, +) + spacing * CGFloat(max(parts.count - 1, 0))
            )
        }
        let parts = options.first { size(of: $0).width <= room.width && size(of: $0).height <= room.height } ?? options[2]
        let stack = frame(of: size(of: parts), centredOn: visible.isNull ? target : visible, in: bounds, avoiding: avoiding)
        var top = stack.maxY
        return parts.map { part, size in
            let rect = CGRect(x: (stack.midX - size.width / 2).rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
            top -= size.height + spacing
            return (part, rect)
        }
    }

    /// A frame of `size` centred on `target`, kept `margin` inside `bounds`, and moved just above or below anything in
    /// `avoiding` it would cover, whichever is nearer the centre and fits on screen.
    static func frame(of size: CGSize, centredOn target: CGRect, in bounds: CGRect, avoiding: [CGRect]) -> CGRect {
        let room = bounds.insetBy(dx: margin, dy: margin)
        func clamped(_ rect: CGRect) -> CGRect {
            var rect = rect
            rect.origin.x = min(max(rect.minX, room.minX), max(room.maxX - rect.width, room.minX))
            rect.origin.y = min(max(rect.minY, room.minY), max(room.maxY - rect.height, room.minY))
            return rect
        }
        let centred = clamped(CGRect(
            x: (target.midX - size.width / 2).rounded(), y: (target.midY - size.height / 2).rounded(), width: size.width, height: size.height
        ))
        guard let blocker = avoiding.first(where: { $0.intersects(centred) }) else {
            return centred
        }
        let above = CGRect(x: centred.minX, y: blocker.maxY + clearance, width: size.width, height: size.height)
        let below = CGRect(x: centred.minX, y: blocker.minY - clearance - size.height, width: size.width, height: size.height)
        let fitting = [above, below]
            .filter { candidate in room.contains(candidate) && !avoiding.contains { $0.intersects(candidate) } }
            .sorted { abs($0.midY - target.midY) < abs($1.midY - target.midY) }
        return fitting.first ?? centred
    }
}

extension WindowInfo {
    /// The name the window pick shows: the window's title, else its app's name, nil when it has neither. The title needs
    /// Screen Recording access, so without it the app's name stands in.
    public var pickName: String? {
        [title, ownerName].lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
}
