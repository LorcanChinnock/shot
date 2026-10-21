import Foundation

/// One edit of an image, as `shot edit` and the MCP `edit_image` tool take it: the image editor's own changes, as JSON.
/// It's checked here, with no file access, so every field is tested; `ShotCommands` applies it to an
/// `EditorDocument`. Lengths and positions are in the input file's pixels, top-left origin, as the capture record's are.
public struct ImageEdit: Equatable, Sendable {
    /// The part to keep, `[x, y, width, height]`, applied last, so it can reach into the padding.
    public var crop: [Double]?
    /// Canvas past the image's edges, `[top, right, bottom, left]`.
    public var pad: [Double]?
    /// Fills the canvas behind the image: a palette name, `#RRGGBB`, or `none` for transparent.
    public var background: String?
    public var style: Style?
    /// Drawn on top of what's there, in the capture record's mark format.
    public var marks: [CaptureMark]
    /// The ids of layers to delete, as the capture record lists them.
    public var remove: [String]
    /// Other images to place on the canvas, above the marks.
    public var place: [Placement]
    /// `1x` scales a Retina image to one pixel per point, as Settings › Scale Retina captures to 1× does.
    public var scale: String?
    /// `png` or `jpeg`; the input's own format when it's one of them, else PNG.
    public var format: Format?

    /// The image's shadow, border and corners. A field left out keeps what the image has.
    public struct Style: Equatable, Sendable {
        /// A preset from `shadows`, or `none`.
        public var shadow: String?
        public var border: Border?
        /// How far the corners are rounded, in pixels; 0 squares them.
        public var corners: Double?

        public init(shadow: String? = nil, border: Border? = nil, corners: Double? = nil) {
            self.shadow = shadow
            self.border = border
            self.corners = corners
        }
    }

    public struct Border: Equatable, Sendable {
        /// One of `borders`, or `none`.
        public var type: String
        /// In pixels; a solid border or an outline is the editor's medium width without one.
        public var width: Double?
        /// A palette name or `#RRGGBB`; white without one. A hairline picks its own.
        public var color: String?

        public init(type: String, width: Double? = nil, color: String? = nil) {
            self.type = type
            self.width = width
            self.color = color
        }
    }

    public struct Placement: Equatable, Sendable {
        /// The image's path. The MCP tool takes only captures in the folder, by path or name.
        public var path: String
        /// Its top-left corner; without one, it goes to the right of the canvas, as a dropped image does.
        public var at: [Double]?
        /// Its width, with the height kept in proportion; without one, its own size in points.
        public var width: Double?

        public init(path: String, at: [Double]? = nil, width: Double? = nil) {
            self.path = path
            self.at = at
            self.width = width
        }
    }

    public enum Format: String, Equatable, Sendable {
        case png, jpeg
    }

    public init(
        crop: [Double]? = nil, pad: [Double]? = nil, background: String? = nil, style: Style? = nil, marks: [CaptureMark] = [],
        remove: [String] = [], place: [Placement] = [], scale: String? = nil, format: Format? = nil
    ) {
        self.crop = crop
        self.pad = pad
        self.background = background
        self.style = style
        self.marks = marks
        self.remove = remove
        self.place = place
        self.scale = scale
        self.format = format
    }

    /// The fields an edit can have, in the order the docs list them.
    public static let fields = ["crop", "pad", "background", "style", "marks", "remove", "place", "scale", "format"]
    /// The shadows the editor's Style popover offers.
    public static let shadows = ["soft", "float", "contact", "glow"]
    /// The borders the editor offers a screenshot; an outline needs see-through pixels.
    public static let borders = ["hairline", "solid", "outline"]
    /// The most padding on a side, so a typo can't make a canvas too big to draw.
    public static let maximumPad: Double = 4096

    /// Whether it changes nothing.
    public var isEmpty: Bool { self == ImageEdit() }

    /// Whether it scales to 1×.
    public var isOneX: Bool { scale != nil }

    // MARK: Parsing

    /// An edit from JSON. The first problem throws a `.data` error that names its field, such as `style.border.width`.
    public static func parse(_ data: Data) throws(ShotCommandError) -> ImageEdit {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw .data("the edit isn't JSON: \(error.localizedDescription)")
        }
        return try parse(value)
    }

    /// An edit from a JSON object, as the MCP tool's arguments hold it, ignoring `ignoring`, such as the tool's `path`.
    public static func parse(_ value: JSONValue, ignoring: Set<String> = []) throws(ShotCommandError) -> ImageEdit {
        guard case let .object(object) = value else {
            throw .data("the edit must be a JSON object with any of \(list(fields))")
        }
        for key in object.keys.sorted() where !fields.contains(key) && !ignoring.contains(key) {
            throw .data("unknown field \"\(key)\"; an edit takes \(list(fields))")
        }
        var edit = ImageEdit()
        if let crop = present(object["crop"]) {
            guard let rect = numbers(crop, count: 4), rect[2] > 0, rect[3] > 0 else {
                throw .data("crop must be [x, y, width, height] in the image's pixels, with a width and height above 0")
            }
            edit.crop = rect
        }
        if let pad = present(object["pad"]) {
            let sides: [Double]? = if case let .number(all) = pad { [all, all, all, all] } else { numbers(pad, count: 4) }
            guard let sides, sides.allSatisfy({ $0 >= 0 && $0 <= maximumPad }) else {
                throw .data("pad must be pixels from 0 to \(Int(maximumPad)), one number for every side or [top, right, bottom, left]")
            }
            edit.pad = sides
        }
        if let background = present(object["background"]) {
            guard let text = background.string, isColor(text, orNone: true) else {
                throw .data("background must be \(colors), or none for transparent")
            }
            edit.background = text
        }
        if let style = present(object["style"]) {
            edit.style = try parseStyle(style)
        }
        if let marks = present(object["marks"]) {
            guard case let .array(items) = marks else {
                throw .data("marks must be an array of marks, in the capture record's format")
            }
            edit.marks = try items.enumerated().map { (index: Int, item: JSONValue) throws(ShotCommandError) -> CaptureMark in
                let mark: CaptureMark
                do {
                    mark = try JSONDecoder().decode(CaptureMark.self, from: JSONEncoder().encode(item))
                } catch {
                    throw .data("marks[\(index)] isn't a mark: it needs a type, and its fields must be the record's")
                }
                if let problem = mark.problem {
                    throw .data("marks[\(index)] (\(mark.type)): \(problem)\(mark.type == "image" ? "; use place" : "")")
                }
                return mark
            }
        }
        if let remove = present(object["remove"]) {
            guard case let .array(items) = remove else {
                throw .data("remove must be an array of layer ids, as the capture record lists them")
            }
            for (index, item) in items.enumerated() {
                guard let id = item.string?.trimmingCharacters(in: .whitespaces), !id.isEmpty else {
                    throw .data("remove[\(index)] must be a layer's id, as the capture record lists it")
                }
                edit.remove.append(id)
            }
        }
        if let place = present(object["place"]) {
            guard case let .array(items) = place else {
                throw .data("place must be an array of images, each {\"path\": …}")
            }
            edit.place = try items.enumerated().map { (index: Int, item: JSONValue) throws(ShotCommandError) -> Placement in
                try parsePlacement(item, field: "place[\(index)]")
            }
        }
        if let scale = present(object["scale"]) {
            guard let text = scale.string?.lowercased(), text == "1x" || text == "1×" else {
                throw .data("scale must be \"1x\", which scales a Retina image to one pixel per point")
            }
            edit.scale = "1x"
        }
        if let format = present(object["format"]) {
            let text = format.string?.lowercased()
            guard let picked = text == "jpg" ? .jpeg : text.flatMap(Format.init(rawValue:)) else {
                throw .data("format must be png or jpeg")
            }
            edit.format = picked
        }
        guard !edit.isEmpty else {
            throw .data("the edit changes nothing; give at least one of \(list(fields))")
        }
        return edit
    }

    private static func parseStyle(_ value: JSONValue) throws(ShotCommandError) -> Style {
        let keys = ["shadow", "border", "corners"]
        guard case let .object(object) = value else {
            throw .data("style must be an object with any of \(list(keys))")
        }
        for key in object.keys.sorted() where !keys.contains(key) {
            throw .data("unknown field \"style.\(key)\"; style takes \(list(keys))")
        }
        var style = Style()
        if let shadow = present(object["shadow"]) {
            guard let name = shadow.string?.lowercased(), shadows.contains(name) || name == "none" else {
                throw .data("style.shadow must be \(list(shadows + ["none"]))")
            }
            style.shadow = name
        }
        if let border = present(object["border"]) {
            style.border = try parseBorder(border)
        }
        if let corners = present(object["corners"]) {
            guard case let .number(radius) = corners, radius.isFinite, radius >= 0 else {
                throw .data("style.corners must be a radius in pixels, 0 or more")
            }
            style.corners = radius
        }
        guard style != Style() else {
            throw .data("style needs at least one of \(list(keys))")
        }
        return style
    }

    private static func parseBorder(_ value: JSONValue) throws(ShotCommandError) -> Border {
        let types = list(borders + ["none"])
        if let name = value.string?.lowercased() {
            guard borders.contains(name) || name == "none" else {
                throw .data("style.border must be \(types), or an object such as {\"type\": \"solid\", \"width\": 4, \"color\": \"white\"}")
            }
            return Border(type: name)
        }
        let keys = ["type", "width", "color"]
        guard case let .object(object) = value else {
            throw .data("style.border must be \(types), or an object such as {\"type\": \"solid\", \"width\": 4, \"color\": \"white\"}")
        }
        for key in object.keys.sorted() where !keys.contains(key) {
            throw .data("unknown field \"style.border.\(key)\"; a border takes \(list(keys))")
        }
        guard let type = object["type"]?.string?.lowercased(), borders.contains(type) || type == "none" else {
            throw .data("style.border.type must be \(types)")
        }
        var border = Border(type: type)
        if let width = present(object["width"]) {
            guard type == "solid" || type == "outline" else {
                throw .data("style.border.width is only for a solid border or an outline; a \(type) has none")
            }
            guard case let .number(pixels) = width, pixels.isFinite, pixels > 0, pixels <= maximumPad else {
                throw .data("style.border.width must be pixels above 0")
            }
            border.width = pixels
        }
        if let color = present(object["color"]) {
            guard type == "solid" || type == "outline" else {
                throw .data("style.border.color is only for a solid border or an outline; a \(type) picks its own")
            }
            guard let text = color.string, isColor(text, orNone: false) else {
                throw .data("style.border.color must be \(colors)")
            }
            border.color = text
        }
        return border
    }

    private static func parsePlacement(_ value: JSONValue, field: String) throws(ShotCommandError) -> Placement {
        let keys = ["path", "at", "width"]
        guard case let .object(object) = value else {
            throw .data("\(field) must be an object such as {\"path\": \"other.png\", \"at\": [40, 40]}")
        }
        for key in object.keys.sorted() where !keys.contains(key) {
            throw .data("unknown field \"\(field).\(key)\"; an image to place takes \(list(keys))")
        }
        guard let path = object["path"]?.string, !path.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw .data("\(field).path must name the image to place")
        }
        var placement = Placement(path: path)
        if let at = present(object["at"]) {
            guard let point = numbers(at, count: 2) else {
                throw .data("\(field).at must be [x, y], its top-left corner in the image's pixels")
            }
            placement.at = point
        }
        if let width = present(object["width"]) {
            guard case let .number(pixels) = width, pixels.isFinite, pixels >= 1, pixels <= 16384 else {
                throw .data("\(field).width must be pixels from 1 to 16384")
            }
            placement.width = pixels
        }
        return placement
    }

    /// `value` unless it's missing or null, which leave a field as it is.
    private static func present(_ value: JSONValue?) -> JSONValue? {
        value == .null ? nil : value
    }

    /// `count` finite numbers, and no strings, which `JSONValue.number` would read.
    private static func numbers(_ value: JSONValue, count: Int) -> [Double]? {
        guard case let .array(items) = value, items.count == count else {
            return nil
        }
        let values = items.compactMap { item -> Double? in
            if case let .number(number) = item, number.isFinite { number } else { nil }
        }
        return values.count == count ? values : nil
    }

    private static let colors = "a palette name (\(list(CaptureMark.paletteNames))) or a colour such as #FF3B30"

    private static func isColor(_ text: String, orNone: Bool) -> Bool {
        let name = text.lowercased()
        return CaptureMark.colorNames.contains(name) || HexColor.components(text) != nil || (orNone && name == "none")
    }

    /// `a, b or c`.
    static func list(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
    }
}
