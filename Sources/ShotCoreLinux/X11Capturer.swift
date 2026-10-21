import CXCB
import Foundation

/// Captures an X11 session, and X11 apps under XWayland, through xcb: the windows `_NET_CLIENT_LIST` names, the displays
/// XRandR gives, and pictures with `GetImage`. A window comes from the offscreen picture XComposite keeps of it, so it's
/// captured whole even behind other windows, without the window shadow a Mac adds. With no compositor running, it asks
/// the server to keep those pictures itself for as long as it's connected; without XComposite, a window is cut from
/// the screen, with whatever covers it. X11 has no scale, so a point is a pixel, and points start at the top left of the
/// primary display.
final class X11Capturer: ScreenCapturer, @unchecked Sendable {
    // xcb is thread-safe, and nothing here changes after init.
    private let connection: OpaquePointer
    private let display: String
    private let screen: UnsafeMutablePointer<xcb_screen_t>
    private var root: xcb_window_t { screen.pointee.root }
    private let atoms: Atoms
    private let composite: Bool
    private let randr: Bool
    /// When this asked the server to keep windows' pictures, since no compositor had: until a covered window draws
    /// itself again, its picture holds what covered it.
    private let redirected: ContinuousClock.Instant?
    /// Whether the pixels of the visual with this ID hold red, green and blue in their low three bytes, as `Bitmap(x11:)`
    /// reads them.
    private let plainVisuals: Set<xcb_visualid_t>
    /// Bits a pixel and a row's padding in bits, by depth.
    private let formats: [UInt8: (bitsPerPixel: Int, scanlinePad: Int)]
    private let mostSignificantFirst: Bool

    /// How long a window takes to draw itself into the picture the server starts keeping of it.
    static let redrawTime = Duration.milliseconds(300)

    var name: String { "x11" }
    var limits: [ScreenCapability: String] { [:] }

    /// Connects to the X server `display` names, such as `:0`.
    init(display: String?) throws(ShotCommandError) {
        guard let display, !display.isEmpty else {
            throw .unavailable("DISPLAY isn't set, so Shot can't tell which X server to capture. Run shot from a terminal in your X11 desktop session.")
        }
        var number: Int32 = 0
        guard let connection = xcb_connect(display, &number), xcb_connection_has_error(connection) == 0, let setup = xcb_get_setup(connection) else {
            throw .unavailable("Shot couldn't connect to the X server at DISPLAY \(display).")
        }
        var screens = xcb_setup_roots_iterator(setup)
        for _ in 0 ..< number {
            xcb_screen_next(&screens)
        }
        guard let screen = screens.data else {
            xcb_disconnect(connection)
            throw .unavailable("The X server at DISPLAY \(display) has no screen \(number).")
        }
        self.connection = connection
        self.display = display
        self.screen = screen
        mostSignificantFirst = setup.pointee.image_byte_order == UInt8(XCB_IMAGE_ORDER_MSB_FIRST.rawValue)

        var formats: [UInt8: (Int, Int)] = [:]
        var formatList = xcb_setup_pixmap_formats_iterator(setup)
        while formatList.rem > 0 {
            let format = formatList.data.pointee
            formats[format.depth] = (Int(format.bits_per_pixel), Int(format.scanline_pad))
            xcb_format_next(&formatList)
        }
        self.formats = formats
        var plain = Set<xcb_visualid_t>()
        var depths = xcb_screen_allowed_depths_iterator(screen)
        while depths.rem > 0 {
            let visuals = UnsafeBufferPointer(start: xcb_depth_visuals(depths.data), count: Int(xcb_depth_visuals_length(depths.data)))
            for visual in visuals where visual.red_mask == 0xFF0000 && visual.green_mask == 0xFF00 && visual.blue_mask == 0xFF {
                plain.insert(visual.visual_id)
            }
            xcb_depth_next(&depths)
        }
        plainVisuals = plain

        let atoms = Atoms(connection, screen: number)
        self.atoms = atoms
        let composite = Self.has(shot_xcb_composite_id(), on: connection) && Self.reply({ xcb_composite_query_version_reply(connection, xcb_composite_query_version(connection, 0, 4), $0) }) {
            ($0.pointee.major_version, $0.pointee.minor_version) >= (0, 2)
        } == true
        self.composite = composite
        randr = Self.has(shot_xcb_randr_id(), on: connection) && Self.reply({ xcb_randr_query_version_reply(connection, xcb_randr_query_version(connection, 1, 3), $0) }) {
            ($0.pointee.major_version, $0.pointee.minor_version) >= (1, 3)
        } == true

        // A compositor already keeps every window's picture. Without one, the server keeps them while this is
        // connected, for its windows and any made later, and stops when it disconnects.
        let compositor = Self.reply({ xcb_get_selection_owner_reply(connection, xcb_get_selection_owner(connection, atoms.compositor), $0) }) { $0.pointee.owner } ?? 0
        if composite, compositor == 0,
           Self.check(connection, xcb_composite_redirect_subwindows_checked(connection, screen.pointee.root, UInt8(XCB_COMPOSITE_REDIRECT_AUTOMATIC.rawValue)))
        {
            redirected = .now
        } else {
            redirected = nil
        }
    }

    deinit {
        xcb_disconnect(connection)
    }

    func displays() async throws(ShotCommandError) -> [ScreenDisplay] {
        try connected()
        let outputs = outputs()
        let origin = outputs[0].frame.origin
        return outputs.map { ScreenDisplay(name: $0.name, frame: $0.frame.offsetBy(dx: -origin.x, dy: -origin.y)) }
    }

    func windows() async throws(ShotCommandError) -> [ScreenWindow] {
        try connected()
        let stack = children(of: root)
        let stackIndex = Dictionary(stack.enumerated().map { ($1, $0) }) { first, _ in first }
        // Without a window manager, the root's own children are the windows.
        let ids = cardinals(root, atoms.clientList)
        let clients = (ids.isEmpty ? stack : ids).compactMap { client($0, stackIndex: stackIndex) }
        let origin = outputs()[0].frame.origin
        return X11Screen.listed(clients).map { client in
            let appID = property(client.id, atoms.windowClass).map(X11Screen.windowClass) ?? ""
            return ScreenWindow(
                id: client.id, app: processName(of: client.id) ?? appID, title: title(of: client.id), appID: appID,
                frame: client.content.offsetBy(dx: -origin.x, dy: -origin.y)
            )
        }
    }

    func capture(display: ScreenDisplay) async throws(ShotCommandError) -> Bitmap {
        try await capture(area: display.frame)
    }

    func capture(window: ScreenWindow) async throws(ShotCommandError) -> Bitmap {
        try connected()
        let id = window.id
        guard let size = geometry(of: id), let top = topLevel(of: id), let inTop = position(of: id, in: top), let onRoot = position(of: id, in: root) else {
            throw .noInput("\(window.app) — \(window.title) closed before Shot could capture it.")
        }
        let shadow = cardinals(id, atoms.gtkFrameExtents).map(Double.init)
        let content = X11Screen.Client(id: id, stackIndex: nil, geometry: CGRect(origin: inTop, size: size.size), shadow: shadow).content
        if composite, let image = await pictureOf(top, area: content) {
            return image
        }
        let onScreen = content.offsetBy(dx: onRoot.x - inTop.x, dy: onRoot.y - inTop.y)
        return try image(of: root, area: onScreen, visual: screen.pointee.root_visual)
    }

    func capture(area: CGRect) async throws(ShotCommandError) -> Bitmap {
        try connected()
        let origin = outputs()[0].frame.origin
        return try image(of: root, area: area.offsetBy(dx: origin.x, dy: origin.y), visual: screen.pointee.root_visual)
    }

    // MARK: Windows

    /// What `X11Screen.listed` needs to know of the window `id`; `nil` when it's gone.
    private func client(_ id: xcb_window_t, stackIndex: [xcb_window_t: Int]) -> X11Screen.Client? {
        guard let attributes = Self.reply({ xcb_get_window_attributes_reply(connection, xcb_get_window_attributes(connection, id), $0) }, { $0.pointee }),
              let size = geometry(of: id), let origin = position(of: id, in: root)
        else {
            return nil
        }
        // Menus and tooltips skip the window manager, and an input-only window shows nothing.
        let shown = attributes.override_redirect == 0 && attributes._class != UInt16(XCB_WINDOW_CLASS_INPUT_ONLY.rawValue)
        // The first type the window gives that's known decides; a window with none is normal.
        let type = cardinals(id, atoms.windowType).first { atoms.windowTypes.contains($0) }
        return X11Screen.Client(
            id: id,
            stackIndex: topLevel(of: id).flatMap { stackIndex[$0] },
            viewable: attributes.map_state == UInt8(XCB_MAP_STATE_VIEWABLE.rawValue),
            normal: shown && type.map(atoms.normalTypes.contains) ?? shown,
            hidden: cardinals(id, atoms.state).contains(atoms.hidden),
            geometry: CGRect(origin: origin, size: size.size),
            shadow: cardinals(id, atoms.gtkFrameExtents).map(Double.init)
        )
    }

    private func title(of id: xcb_window_t) -> String {
        if let name = property(id, atoms.name), let title = String(data: name, encoding: .utf8) {
            return title
        }
        return property(id, XCB_ATOM_WM_NAME.rawValue).map(X11Screen.legacyText) ?? ""
    }

    /// The name of the process `_NET_WM_PID` names, such as `gnome-terminal-server`.
    private func processName(of id: xcb_window_t) -> String? {
        guard let pid = cardinals(id, atoms.pid).first,
              let name = try? String(contentsOfFile: "/proc/\(pid)/comm", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else {
            return nil
        }
        return name
    }

    // MARK: Displays

    /// The displays in the root window's pixels, the primary one first; the whole root as one without XRandR.
    private func outputs() -> [X11Screen.Output] {
        let whole = X11Screen.Output(name: "screen", frame: CGRect(x: 0, y: 0, width: Int(screen.pointee.width_in_pixels), height: Int(screen.pointee.height_in_pixels)))
        guard randr else {
            return [whole]
        }
        let primary = Self.reply({ xcb_randr_get_output_primary_reply(connection, xcb_randr_get_output_primary(connection, root), $0) }) { $0.pointee.output } ?? 0
        let found: [X11Screen.Output] = Self.reply({ xcb_randr_get_screen_resources_current_reply(connection, xcb_randr_get_screen_resources_current(connection, root), $0) }) { resources in
            let time = resources.pointee.config_timestamp
            let ids = UnsafeBufferPointer(start: xcb_randr_get_screen_resources_current_outputs(resources), count: Int(xcb_randr_get_screen_resources_current_outputs_length(resources)))
            return ids.compactMap { id -> X11Screen.Output? in
                guard let (name, crtc) = Self.reply({ xcb_randr_get_output_info_reply(connection, xcb_randr_get_output_info(connection, id, time), $0) }, { info in
                    let name = UnsafeBufferPointer(start: xcb_randr_get_output_info_name(info), count: Int(xcb_randr_get_output_info_name_length(info)))
                    return (String(decoding: name, as: UTF8.self), info.pointee.crtc)
                }), crtc != 0,
                    let frame = Self.reply({ xcb_randr_get_crtc_info_reply(connection, xcb_randr_get_crtc_info(connection, crtc, time), $0) }, { crtc in
                        CGRect(x: Int(crtc.pointee.x), y: Int(crtc.pointee.y), width: Int(crtc.pointee.width), height: Int(crtc.pointee.height))
                    })
                else {
                    return nil
                }
                return X11Screen.Output(name: name, frame: frame, primary: id == primary)
            }
        } ?? []
        let displays = X11Screen.displays(found)
        return displays.isEmpty ? [whole] : displays
    }

    // MARK: Pictures

    /// The part of `top`'s offscreen picture `area` covers, in `top`'s pixels inside its border; `nil` when the server
    /// keeps none, so the screen has to do.
    private func pictureOf(_ top: xcb_window_t, area: CGRect) async -> Bitmap? {
        if let redirected {
            let wait = Self.redrawTime - (ContinuousClock.now - redirected)
            if wait > .zero {
                try? await Task.sleep(for: wait)
            }
        }
        guard let attributes = Self.reply({ xcb_get_window_attributes_reply(connection, xcb_get_window_attributes(connection, top), $0) }, { $0.pointee }),
              let frame = geometry(of: top)
        else {
            return nil
        }
        let pixmap = xcb_generate_id(connection)
        guard Self.check(connection, xcb_composite_name_window_pixmap_checked(connection, top, pixmap)) else {
            return nil
        }
        defer {
            xcb_free_pixmap(connection, pixmap)
            xcb_flush(connection)
        }
        // The picture includes the border.
        let border = CGFloat(frame.border)
        return try? image(of: pixmap, area: area.offsetBy(dx: border, dy: border), visual: attributes.visual)
    }

    /// What `drawable` shows in `area`, cut to its bounds, through `GetImage`.
    private func image(of drawable: xcb_drawable_t, area: CGRect, visual: xcb_visualid_t) throws(ShotCommandError) -> Bitmap {
        guard let bounds = geometry(of: drawable) else {
            throw .internal("The X server lost the window before Shot could capture it.")
        }
        let shown = area.integral.intersection(CGRect(origin: .zero, size: bounds.size))
        guard !shown.isNull, shown.width >= 1, shown.height >= 1 else {
            throw .data("\(Self.text(area)) is off the screen.")
        }
        let (x, y, width, height) = (Int16(shown.minX), Int16(shown.minY), UInt16(shown.width), UInt16(shown.height))
        let cookie = xcb_get_image(connection, UInt8(XCB_IMAGE_FORMAT_Z_PIXMAP.rawValue), drawable, x, y, width, height, .max)
        let result = Self.reply({ xcb_get_image_reply(connection, cookie, $0) }) { reply -> Result<Bitmap, ShotCommandError> in
            let depth = reply.pointee.depth
            guard depth == 24 || depth == 32, let format = formats[depth], format.bitsPerPixel == 32, plainVisuals.contains(visual) else {
                return .failure(.unavailable("Shot can capture only 24- and 32-bit colour on X11, and this is \(depth)-bit."))
            }
            let bytesPerRow = (Int(width) * 32 + format.scanlinePad - 1) / format.scanlinePad * format.scanlinePad / 8
            let data = Data(bytesNoCopy: xcb_get_image_data(reply), count: Int(xcb_get_image_data_length(reply)), deallocator: .none)
            guard let bitmap = Bitmap(x11: data, width: Int(width), height: Int(height), bytesPerRow: bytesPerRow, mostSignificantFirst: mostSignificantFirst, alpha: depth == 32) else {
                return .failure(.internal("The X server gave a picture too small for its size."))
            }
            return .success(bitmap)
        }
        guard let result else {
            throw .internal("The X server couldn't give the picture of \(Self.text(area)).")
        }
        return try result.get()
    }

    // MARK: Requests

    private func connected() throws(ShotCommandError) {
        guard xcb_connection_has_error(connection) == 0 else {
            throw .unavailable("Shot lost its connection to the X server at DISPLAY \(display). Stop shot serve with pkill -f \"shot serve\"; the next capture starts it again.")
        }
    }

    private func children(of window: xcb_window_t) -> [xcb_window_t] {
        Self.reply({ xcb_query_tree_reply(connection, xcb_query_tree(connection, window), $0) }) { tree in
            Array(UnsafeBufferPointer(start: xcb_query_tree_children(tree), count: Int(xcb_query_tree_children_length(tree))))
        } ?? []
    }

    /// The child of the root that holds `window`: the frame the window manager put it in, or the window itself.
    private func topLevel(of window: xcb_window_t) -> xcb_window_t? {
        var window = window
        while let parent = Self.reply({ xcb_query_tree_reply(connection, xcb_query_tree(connection, window), $0) }, { $0.pointee.parent }), parent != 0 {
            if parent == root {
                return window
            }
            window = parent
        }
        return nil
    }

    /// The size of `drawable`, its depth and its border's width.
    private func geometry(of drawable: xcb_drawable_t) -> (size: CGSize, depth: UInt8, border: UInt16)? {
        Self.reply({ xcb_get_geometry_reply(connection, xcb_get_geometry(connection, drawable), $0) }) {
            (CGSize(width: Int($0.pointee.width), height: Int($0.pointee.height)), $0.pointee.depth, $0.pointee.border_width)
        }
    }

    /// Where `window`'s top left is in `other`, inside both their borders.
    private func position(of window: xcb_window_t, in other: xcb_window_t) -> CGPoint? {
        Self.reply({ xcb_translate_coordinates_reply(connection, xcb_translate_coordinates(connection, window, other, 0, 0), $0) }) {
            CGPoint(x: Int($0.pointee.dst_x), y: Int($0.pointee.dst_y))
        }
    }

    private func property(_ window: xcb_window_t, _ atom: xcb_atom_t) -> Data? {
        let cookie = xcb_get_property(connection, 0, window, atom, XCB_ATOM_ANY.rawValue, 0, 1 << 16)
        return Self.reply({ xcb_get_property_reply(connection, cookie, $0) }) { reply -> Data? in
            guard reply.pointee.type != 0, let value = xcb_get_property_value(reply) else {
                return nil
            }
            return Data(bytes: value, count: Int(xcb_get_property_value_length(reply)))
        } ?? nil
    }

    /// A property of 32-bit values, such as a list of windows or atoms; empty when it's not set.
    private func cardinals(_ window: xcb_window_t, _ atom: xcb_atom_t) -> [UInt32] {
        guard let data = property(window, atom) else {
            return []
        }
        return data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count / 4 * 4, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self) }
        }
    }

    /// What `read` makes of the reply `wait` waits for, which it then frees; `nil` when the server answered with an
    /// error instead, as it does for a window that's gone.
    private static func reply<Reply, Value>(
        _ wait: (UnsafeMutablePointer<UnsafeMutablePointer<xcb_generic_error_t>?>) -> UnsafeMutablePointer<Reply>?,
        _ read: (UnsafeMutablePointer<Reply>) -> Value
    ) -> Value? {
        var error: UnsafeMutablePointer<xcb_generic_error_t>?
        let reply = wait(&error)
        free(error)
        guard let reply else {
            return nil
        }
        defer { free(reply) }
        return read(reply)
    }

    /// Whether a request that has no reply worked.
    private static func check(_ connection: OpaquePointer, _ cookie: xcb_void_cookie_t) -> Bool {
        guard let error = xcb_request_check(connection, cookie) else {
            return true
        }
        free(error)
        return false
    }

    private static func has(_ extensionID: OpaquePointer, on connection: OpaquePointer) -> Bool {
        xcb_get_extension_data(connection, extensionID)?.pointee.present == 1
    }

    private static func text(_ area: CGRect) -> String {
        "The area at \(Int(area.minX)),\(Int(area.minY)), \(Int(area.width))×\(Int(area.height)) points,"
    }
}

/// The atoms `X11Capturer` reads windows with, interned once.
private struct Atoms {
    let clientList, name, pid, windowClass, windowType, state, hidden, gtkFrameExtents, compositor: xcb_atom_t
    /// The window types listed, and every type a window may give.
    let normalTypes, windowTypes: Set<xcb_atom_t>

    static let types = ["NORMAL", "DIALOG", "UTILITY", "DESKTOP", "DOCK", "TOOLBAR", "MENU", "SPLASH", "DROPDOWN_MENU", "POPUP_MENU", "TOOLTIP", "NOTIFICATION", "COMBO", "DND"]

    init(_ connection: OpaquePointer, screen: Int32) {
        let names = [
            "_NET_CLIENT_LIST", "_NET_WM_NAME", "_NET_WM_PID", "_NET_WM_WINDOW_TYPE", "_NET_WM_STATE", "_NET_WM_STATE_HIDDEN", "_GTK_FRAME_EXTENTS",
            "_NET_WM_CM_S\(screen)",
        ] + Self.types.map { "_NET_WM_WINDOW_TYPE_\($0)" }
        // Asked all at once, then read, so it's one round trip.
        let cookies = names.map { xcb_intern_atom(connection, 0, UInt16($0.utf8.count), $0) }
        let atoms = cookies.map { cookie in
            var error: UnsafeMutablePointer<xcb_generic_error_t>?
            let reply = xcb_intern_atom_reply(connection, cookie, &error)
            free(error)
            defer { free(reply) }
            return reply?.pointee.atom ?? 0
        }
        (clientList, name, pid, windowType, state, hidden, gtkFrameExtents, compositor) = (atoms[0], atoms[1], atoms[2], atoms[3], atoms[4], atoms[5], atoms[6], atoms[7])
        windowClass = XCB_ATOM_WM_CLASS.rawValue
        let types = atoms[8...]
        windowTypes = Set(types)
        normalTypes = Set(types.prefix(3))
    }
}
