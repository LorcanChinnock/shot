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
