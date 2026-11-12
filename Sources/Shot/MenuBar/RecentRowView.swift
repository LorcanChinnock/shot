import AppKit
import ShotCore

/// The menu's Recent row: up to four thumbnails of the newest captures. Clicking one opens it in its editor, and dragging
/// one drops the file into another app. A menu keeps the arrow keys to itself, so the keyboard reaches the captures through
/// `StatusMenu`: Down highlights this row, and Right opens a native submenu listing them.
@MainActor
final class RecentRowView: NSView {
    static let thumbnailSize = NSSize(width: 60, height: 40)
    static let gap: CGFloat = 6
    /// Lines the first thumbnail up with the icons in the rows above.
    static let inset: CGFloat = 14
    static let padding = NSEdgeInsets(top: 2, left: inset, bottom: 6, right: inset)

    var onOpen: ((GalleryItem) -> Void)?
    var entries: [RecentCapturesStore.Entry] = [] {
        didSet { layoutThumbnails() }
    }

    /// Whether the keyboard has put the menu's highlight on this row, which draws it like a highlighted row.
    var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    private var thumbnails: [RecentThumbnailView] = []

    init() {
        let count = CGFloat(RecentCaptures.limit)
        let width = Self.padding.left + count * Self.thumbnailSize.width + (count - 1) * Self.gap + Self.padding.right
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.padding.top + Self.thumbnailSize.height + Self.padding.bottom))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Recent captures"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func layoutThumbnails() {
        while thumbnails.count > entries.count {
            thumbnails.removeLast().removeFromSuperview()
        }
        while thumbnails.count < entries.count {
            let view = RecentThumbnailView()
            view.onOpen = { [weak self] item in self?.onOpen?(item) }
            addSubview(view)
            thumbnails.append(view)
        }
        for (index, view) in thumbnails.enumerated() {
            let x = Self.padding.left + CGFloat(index) * (Self.thumbnailSize.width + Self.gap)
            view.frame = NSRect(origin: NSPoint(x: x, y: Self.padding.bottom), size: Self.thumbnailSize)
            view.entry = entries[index]
        }
        setAccessibilityChildren(thumbnails)
    }

    func menuClosed() {
        isHighlighted = false
        thumbnails.forEach { $0.isHovered = false }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else {
            return
        }
        // Behind the thumbnails, as far in as the menu's own row highlight sits.
        let highlight = NSRect(x: 5, y: Self.padding.bottom - 3, width: bounds.width - 10, height: Self.thumbnailSize.height + 6)
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: highlight, xRadius: Theme.Radius.control, yRadius: Theme.Radius.control).fill()
    }
}

/// One capture in the Recent row: its picture cropped to fill, a hairline edge, and a badge with its type or length.
@MainActor
final class RecentThumbnailView: NSView, NSDraggingSource {
    var onOpen: ((GalleryItem) -> Void)?
    var entry: RecentCapturesStore.Entry? {
        didSet {
            needsDisplay = true
            describe()
        }
    }

    var isHovered = false {
        didSet { needsDisplay = true }
    }

    private var mouseDownPoint: NSPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    // MARK: Drawing

    /// The thumbnail's hairline edge: ink at 12% in light, as the board draws it, and white at 12% in dark.
    private static let edge = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.12)
            : NSColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x1A / 255, alpha: 0.12)
    }

    private static let badgeFill = NSColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x1A / 255, alpha: 0.75)

    override func draw(_ dirtyRect: NSRect) {
        let radius = Theme.Radius.tiny
        Self.drawPicture(entry?.thumbnail?.image, in: bounds, radius: radius)

        Self.edge.setStroke()
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        edge.lineWidth = 1
        edge.stroke()

        if let entry, let badge = RecentCaptures.badge(for: entry.item, duration: entry.thumbnail?.duration) {
            drawBadge(badge)
        }

        if isHovered {
            // The menu's own highlight colour, so the thumbnail under the pointer reads as picked the way a row does.
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    /// `image` cropped to fill `rect` with rounded corners, or a placeholder while it's still decoding.
    static func drawPicture(_ image: NSImage?, in rect: NSRect, radius: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        if let image, image.size.width > 0, image.size.height > 0 {
            let scale = max(rect.width / image.size.width, rect.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        } else {
            NSColor.quaternaryLabelColor.setFill()
            rect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBadge(_ text: String) {
        let font = NSFont.systemFont(ofSize: 8, weight: .bold)
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = label.size()
        let badge = NSRect(x: bounds.maxX - 3 - size.width - 6, y: 3, width: size.width + 6, height: ceil(size.height))
        Self.badgeFill.setFill()
        NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()
        label.draw(at: NSPoint(x: badge.minX + 3, y: badge.minY))
    }

    // MARK: Accessibility

    private func describe() {
        guard let item = entry?.item else {
            return
        }
        setAccessibilityLabel(item.recentLabel)
        setAccessibilityHelp(String(localized: "Opens it to edit. Drag it into another app to use the file there."))
        toolTip = item.name
    }

    override func accessibilityPerformPress() -> Bool {
        guard let item = entry?.item else {
            return false
        }
        onOpen?(item)
        return true
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let entry else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 3 else {
            return
        }
        mouseDownPoint = nil
        let dragged = NSDraggingItem(pasteboardWriter: entry.item.url as NSURL)
        dragged.setDraggingFrame(bounds, contents: entry.thumbnail?.image ?? NSWorkspace.shared.icon(forFile: entry.item.url.path))
        beginDraggingSession(with: [dragged], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil, let item = entry?.item else {
            return
        }
        mouseDownPoint = nil
        onOpen?(item)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] {
            enclosingMenuItem?.menu?.cancelTracking()
        }
    }
}

extension GalleryItem {
    /// How the menu names a recent capture, for VoiceOver and the keyboard's list: its kind, then how long ago.
    var recentLabel: String {
        let kind = switch self.kind {
        case .image: String(localized: "Screenshot")
        case .gif: String(localized: "GIF")
        case .video: String(localized: "Recording")
        }
        let when = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
        return String(localized: "\(kind), \(when)", comment: "A capture in the menu's Recent row: the kind of capture, then how long ago, such as \"Screenshot, 5 minutes ago\"")
    }
}
