import CoreGraphics

/// Picks the page of a browser window out of the web areas its accessibility tree reports.
public enum BrowserPage {
    public static let minimumSize: CGFloat = 100

    /// The largest web area that lies inside `window` and is big enough to be a page, so an embedded frame or an
    /// off-screen area is never taken for it. Nil when none qualifies.
    public static func page(among webAreas: [CGRect], inside window: CGRect) -> CGRect? {
        webAreas
            .map { $0.intersection(window) }
            .filter { !$0.isNull && $0.width >= minimumSize && $0.height >= minimumSize }
            .max { $0.width * $0.height < $1.width * $1.height }
    }
}

/// How far a browser's page sits in from the edges of its window. The toolbar keeps its size when the window is
/// resized, so the page of a resized window is the window less these insets.
public struct PageInsets: Equatable, Sendable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat

    public init(window: CGRect, page: CGRect) {
        top = page.minY - window.minY
        left = page.minX - window.minX
        bottom = window.maxY - page.maxY
        right = window.maxX - page.maxX
    }

    /// The page of `window`, in the space `window` is in.
    public func page(in window: CGRect) -> CGRect {
        CGRect(
            x: window.minX + left,
            y: window.minY + top,
            width: max(1, window.width - left - right),
            height: max(1, window.height - top - bottom)
        )
    }
}

public enum AspectFit {
    /// The largest rect of `content`'s shape that fits centred in `container`, with origin at the container's top left.
    public static func rect(for content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }
}
