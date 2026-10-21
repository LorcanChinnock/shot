import Foundation

/// What `X11Capturer` decides without the X server: which windows `shot windows` lists and in what order, which display
/// is the first and where points start, and how the server's pixels become a `Bitmap`. X11 has no scale of its own, so
/// a point is a pixel, and points start at the top left of the first display rather than of the root window.
public enum X11Screen {
    /// The smallest window listed, in points each way, as on a Mac.
    public static let minimumWindowSide = 40.0

    /// A client window, as `_NET_CLIENT_LIST` names it, with what the server says about it.
    public struct Client: Equatable, Sendable {
        public var id: UInt32
        /// Where its top-level window, the client or the frame the window manager put it in, is among the root's
        /// children, which the server lists back to front; `nil` when it's not among them.
        public var stackIndex: Int?
        /// Whether it and every window holding it is mapped, which a minimized window isn't.
        public var viewable: Bool
        /// Whether its `_NET_WM_WINDOW_TYPE` is normal, a dialog or a utility window, or it has none, rather than a dock,
        /// desktop, menu or the like.
        public var normal: Bool
        /// Whether `_NET_WM_STATE` says it's hidden, as a minimized window is.
        public var hidden: Bool
        /// In the root window's pixels.
        public var geometry: CGRect
        /// `_GTK_FRAME_EXTENTS`: the shadow a window that draws its own frame keeps around it, as left, right, top and
        /// bottom.
        public var shadow: [Double]

        public init(id: UInt32, stackIndex: Int?, viewable: Bool = true, normal: Bool = true, hidden: Bool = false, geometry: CGRect, shadow: [Double] = []) {
            self.id = id
            self.stackIndex = stackIndex
            self.viewable = viewable
            self.normal = normal
            self.hidden = hidden
            self.geometry = geometry
            self.shadow = shadow
        }

        /// The window without its shadow, in the root window's pixels.
        public var content: CGRect {
            guard shadow.count == 4 else {
                return geometry
            }
            let (left, right, top, bottom) = (shadow[0], shadow[1], shadow[2], shadow[3])
            return CGRect(x: geometry.minX + left, y: geometry.minY + top, width: geometry.width - left - right, height: geometry.height - top - bottom)
        }
    }

    /// The clients `shot windows` lists, front to back: those on screen and normal, at least 40 points each way once
    /// their shadow is cut. Two clients in one frame keep the order the window manager listed them in.
    public static func listed(_ clients: [Client]) -> [Client] {
        let shown = clients.enumerated().compactMap { order, client -> (stack: Int, order: Int, client: Client)? in
            guard let stack = client.stackIndex, client.viewable, client.normal, !client.hidden,
                  client.content.width >= minimumWindowSide, client.content.height >= minimumWindowSide
            else {
                return nil
            }
            return (stack, order, client)
        }
        return shown.sorted { a, b in a.stack != b.stack ? a.stack > b.stack : a.order < b.order }.map(\.client)
    }

    /// A display, as XRandR gives it: an output and the CRTC that shows it.
    public struct Output: Equatable, Sendable {
        public var name: String
        public var crtc: UInt32
        /// In the root window's pixels.
        public var frame: CGRect
        public var primary: Bool

        public init(name: String, crtc: UInt32, frame: CGRect, primary: Bool = false) {
            self.name = name
            self.crtc = crtc
            self.frame = frame
            self.primary = primary
        }
    }

    /// The outputs that show something, the primary one first, then left to right and top to bottom, one an output a
    /// mirror shows too.
    public static func displays(_ outputs: [Output]) -> [Output] {
        var seen = Set<UInt32>()
        let shown = outputs.filter { !$0.frame.isEmpty && seen.insert($0.crtc).inserted }
        return shown.sorted { a, b in
            if a.primary != b.primary {
                return a.primary
            }
            return (a.frame.minX, a.frame.minY) < (b.frame.minX, b.frame.minY)
        }
    }

    /// The first `WM_CLASS` string after the instance, which names the app, such as `firefox` or `Gnome-terminal`.
    public static func windowClass(_ value: Data) -> String {
        let parts = value.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        return parts.count > 1 ? parts[1] : ""
    }

    /// A `WM_NAME` in Latin-1, as `STRING` properties are, or UTF-8, as most apps write it anyway.
    public static func legacyText(_ value: Data) -> String {
        String(data: value, encoding: .utf8) ?? String(data: value, encoding: .isoLatin1) ?? ""
    }
}

extension Bitmap {
    /// The pixels of an X11 image in `ZPixmap` format at 32 bits a pixel, red, green and blue in the low three bytes of
    /// each pixel, in the byte order the server gives. With `alpha`, as in a 32-bit window, the top byte is its alpha,
    /// already premultiplied as X's are; without, the image is opaque. `nil` when `data` is too short.
    public init?(x11 data: Data, width: Int, height: Int, bytesPerRow: Int, mostSignificantFirst: Bool, alpha: Bool) {
        guard width > 0, height > 0, bytesPerRow >= width * 4, data.count >= bytesPerRow * (height - 1) + width * 4 else {
            return nil
        }
        // Byte i of a pixel, least significant first: blue, green, red and alpha.
        let (b, g, r, a) = mostSignificantFirst ? (3, 2, 1, 0) : (0, 1, 2, 3)
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                for y in 0 ..< height {
                    var i = y * bytesPerRow, o = y * width * 4
                    for _ in 0 ..< width {
                        out[o] = source[i + r]
                        out[o + 1] = source[i + g]
                        out[o + 2] = source[i + b]
                        out[o + 3] = alpha ? source[i + a] : 255
                        i += 4
                        o += 4
                    }
                }
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}
