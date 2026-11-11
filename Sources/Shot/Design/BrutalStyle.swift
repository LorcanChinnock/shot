import AppKit
import ShotCore
import SwiftUI

/// Design tokens and components. The values come from `docs/redesign/spec.md` (#1068).
enum Brutal {
    // MARK: Colour
    // Warm neutrals in both appearances, with yellow the only interface accent. Dark shows depth by lightness: the window is
    // darkest, groups sit a step lighter and control fills lighter still. Text on an accent fill stays near-black either way,
    // because a surface with a light fill lays out its content in the light appearance.

    /// Window and canvas background.
    static let window = Color(light: Color(hex: 0xF7F6F3), dark: Color(hex: 0x1C1C1F))
    /// Sidebars, under the see-through material.
    static let sidebar = Color(light: Color(hex: 0xECE9E3), dark: Color(hex: 0x242427))
    /// Grouped panels, cards and fields.
    static let group = Color(light: .white, dark: Color(hex: 0x2C2C30))
    /// Secondary buttons in dark, quiet fills in light.
    static let controlFill = Color(light: Color(hex: 0xF1EFEA), dark: Color(hex: 0x3A3A3F))
    /// The thumb of a segmented control.
    static let selectedSegment = Color(light: .white, dark: Color(hex: 0x4A4A50))

    /// Body text and icons: near-black in light mode, warm off-white in dark. Text on an accent fill stays near-black.
    static let ink = Color(light: Color(hex: 0x16161A), dark: Color(hex: 0xEDEBE6))
    static let secondaryText = Color(light: Color(hex: 0x55545A), dark: Color(hex: 0xA9A7AE))
    /// Captions, section labels and key hints.
    static let tertiaryText = Color(light: Color(hex: 0x6B6A70), dark: Color(hex: 0xA9A7AE))
    /// Plain buttons and links, where yellow itself fails contrast on a light window.
    static let accentText = Color(light: Color(hex: 0x8A6A00), dark: Color(hex: 0xF2CC4A))
    static let disabledText = Color(light: Color(hex: 0x16161A).opacity(0.35), dark: Color(hex: 0xEDEBE6).opacity(0.35))

    /// Ink outlines and hard drops: near-black in both appearances.
    static let line = Color(light: Color(hex: 0x16161A), dark: Color(hex: 0x050507))
    /// The only interface accent: the ink control, the selected tool, focus and toggles. Softer in dark so it doesn't glare.
    static let accent = Color(light: Color(hex: 0xFFD43B), dark: Color(hex: 0xF2CC4A))
    /// Recording, and destructive buttons.
    static let record = Color(light: Color(hex: 0xE5352B), dark: Color(hex: 0xFF453A))
    /// Selected marks, layers and files.
    static let selection = Color(hex: 0x2B7FFF)
    /// Status dots and tags.
    static let success = Color(hex: 0x34C759)
    /// A success tag's fill, such as an allowed permission's.
    static let successFill = Color(light: Color(hex: 0xE3F4E6), dark: Color(hex: 0x34C759).opacity(0.18))
    /// A success tag's text, darker than `success` in light so it holds 4.5:1 on `successFill`.
    static let successText = Color(light: Color(hex: 0x1F6B3A), dark: Color(hex: 0x7DDE97))

    /// Edges of groups and cards.
    static let hairline = Color(light: Color(hex: 0x16161A).opacity(0.08), dark: .white.opacity(0.08))
    /// Edges of buttons and pop-up menus.
    static let controlEdge = Color(light: Color(hex: 0x16161A).opacity(0.14), dark: .white.opacity(0.12))
    /// Rows inside a group.
    static let separator = Color(light: Color(hex: 0x16161A).opacity(0.07), dark: .white.opacity(0.08))
    /// Search fields, segmented tracks and tag chips.
    static let fieldFill = Color(light: Color(hex: 0x16161A).opacity(0.06), dark: .white.opacity(0.07))
    /// Toolbar buttons on hover, and toolbar toggles that are on.
    static let hover = Color(light: Color(hex: 0x16161A).opacity(0.07), dark: .white.opacity(0.08))

    /// A secondary button: white in light, the control fill in dark.
    static let secondaryFill = Color(light: .white, dark: Color(hex: 0x3A3A3F))
    /// Red text and edges on destructive secondary, plain and toolbar buttons, darker than record red so text holds 4.5:1.
    static let destructiveText = Color(light: Color(hex: 0xC4271E), dark: Color(hex: 0xFF7B72))
    /// The 4 pt halo around a control with keyboard focus: the accent at 60%.
    static let focusRing = Color(hex: 0xFFD43B).opacity(0.6)

    /// The neutral fill under ink: buttons, chips, menus and floating panels. Replaced by `group` and `controlFill` as each
    /// screen is rebuilt.
    static let paper = Color(light: .white, dark: Color(hex: 0x3A3A3F))
    /// A glass card's tint. A card is now a solid group; the flag stays so call sites don't change.
    static let glass = group
    /// A recessed fill below `paper`: a toggle that's off, a segmented control's track, an unlit meter bar.
    static let well = Color(light: Color(hex: 0x16161A).opacity(0.06), dark: Color(hex: 0x1C1C1F))
    /// A toggle's knob while it's off.
    static let knob = Color(light: .white, dark: Color(hex: 0x8E8B93))
    /// `ink`, `yellow`, `red` and `mint` for AppKit drawing, in their light-mode colours, for marks drawn over a capture or the screen.
    /// `inkNS` is also `line` in either appearance. Chrome that follows the appearance uses `NSColor(Brutal.paper)` and friends.
    static var inkNS: NSColor { NSColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x1A / 255, alpha: 1) }
    static var yellowNS: NSColor { NSColor(srgbRed: 1, green: 0xD4 / 255, blue: 0x3B / 255, alpha: 1) }
    static var redNS: NSColor { NSColor(srgbRed: 0xE5 / 255, green: 0x35 / 255, blue: 0x2B / 255, alpha: 1) }
    static var mintNS: NSColor { NSColor(srgbRed: 0x4F / 255, green: 0xE3 / 255, blue: 0xB5 / 255, alpha: 1) }
    static let border: CGFloat = 3
    static let radius: CGFloat = 10
    static let shadow: CGFloat = 4

    /// A sidebar icon's tile and glyph. Tints appear only behind a sidebar icon, never as a fill.
    struct SidebarTint {
        let tile: Color
        let icon: Color

        init(tile: (light: UInt32, dark: UInt32), icon: (light: UInt32, dark: UInt32)) {
            self.tile = Color(light: Color(hex: tile.light), dark: Color(hex: tile.dark))
            self.icon = Color(light: Color(hex: icon.light), dark: Color(hex: icon.dark))
        }

        static let general = SidebarTint(tile: (0xF0EDE6, 0x3A3A3F), icon: (0x55545A, 0xCFCDD4))
        static let capture = SidebarTint(tile: (0xFFE0EE, 0x4A2336), icon: (0xC2306E, 0xFF8DBE))
        static let quickAccess = SidebarTint(tile: (0xDCEFFF, 0x1E3550), icon: (0x1D6FB8, 0x7DBBFF))
        static let recording = SidebarTint(tile: (0xFFE1DE, 0x4A2220), icon: (0xC4271E, 0xFF7B72))
        static let shortcuts = SidebarTint(tile: (0xFFE9D3, 0x4A3118), icon: (0xB35A00, 0xFFB366))
        static let about = SidebarTint(tile: (0xEAF6D2, 0x2E3D1A), icon: (0x4E7A0E, 0xA8D86A))
        /// Open Gallery's tile, under a control edge.
        static let gallery = SidebarTint(tile: (0xFFFFFF, 0x3A3A3F), icon: (0x3A393F, 0xCFCDD4))
        /// The selected row's tile, in both appearances.
        static let selected = SidebarTint(tile: (0xFFFFFF, 0xFFFFFF), icon: (0x16161A, 0x16161A))
    }

    /// The gallery sidebar's icons, drawn in these colours without a tile.
    static let screenshotsIcon = Color(light: Color(hex: 0x5B4BD6), dark: Color(hex: 0xA99BFF))
    static let recordingsIcon = Color(light: Color(hex: 0xC4271E), dark: Color(hex: 0xFF7B72))
    static let gifsIcon = Color(light: Color(hex: 0x1D6FB8), dark: Color(hex: 0x7DBBFF))

    // MARK: Shape

    /// Corner radii: Control 6, Group 10, Panel 14, and full (height ÷ 2) for floating panels, toasts, toggles and chips.
    enum Radius {
        /// Buttons, fields, pop-up menus, toolbar buttons and menu rows.
        static let control: CGFloat = 6
        /// Grouped panels, tiles and thumbnails.
        static let group: CGFloat = 10
        /// Side panels, Quick Access cards, dialogs and cards.
        static let panel: CGFloat = 14
        /// Timeline clips and thumbnails.
        static let tiny: CGFloat = 4
        /// Chips and small buttons.
        static let chip = control
        /// Options inside a bordered group, such as segments, tiles and layer rows, which sit `groupInset` in.
        static let inset = control
        /// Buttons.
        static let button = control
        /// A radius that makes a shape of this height a pill.
        static func full(height: CGFloat) -> CGFloat { height / 2 }
    }

    // MARK: Depth
    // Rest: a 1 pt control edge and `0 1px 1px` at 6% ink, for secondary buttons and pop-up menus.
    // Group: a 1 pt hairline and `0 1px 2px` at 4% ink, for grouped panels and cards.
    // Float: a 0.5 pt edge and `0 8px 24px` at 16% ink, for popovers, menus, tooltips and the style bar.
    // Ink: a 1.5 pt ink outline and a `0 2px 0` ink drop, for the one ink control per screen.

    /// Depth levels for `depth(_:radius:)`.
    enum Depth {
        case rest, group, float
    }

    // Spacing rule: keep at least `minGap` of clear space between any two ink lines, shadows included.
    static let minGap: CGFloat = 6
    /// Content inset from the window border.
    static let windowInset: CGFloat = 24
    /// Inset inside a bordered group that holds other bordered controls.
    static let groupInset: CGFloat = 7
    static let sectionGap: CGFloat = 16

    /// The accent, under its old name. New code uses `accent`.
    static let yellow = accent
    /// The eight bright colours the old design filled surfaces with. Each screen drops them as it is rebuilt; the sidebar tints
    /// above replace them behind icons. `red` is now the record red.
    static let red = record
    static let pink = Color(light: Color(hex: 0xFF7AB6), dark: Color(hex: 0xE58BB3))
    static let mint = Color(light: Color(hex: 0x4FE3B5), dark: Color(hex: 0x62CDAB))
    static let sky = Color(light: Color(hex: 0x6FC3FF), dark: Color(hex: 0x80BBE6))
    static let violet = Color(light: Color(hex: 0x9B8CFF), dark: Color(hex: 0x9C92E3))
    static let orange = Color(light: Color(hex: 0xFF9F43), dark: Color(hex: 0xE8A060))
    static let lime = Color(light: Color(hex: 0xB6E24B), dark: Color(hex: 0xB1CF62))

    // MARK: Type
    // SF Pro at native sizes, through `ScaledFont`, so Settings › Text size still scales it.

    /// Onboarding and empty states only: the one heavy weight.
    static let display = ScaledFont.scaled(28, weight: .heavy)
    /// Window and page titles.
    static let windowTitle = ScaledFont.scaled(20, weight: .bold)
    /// Settings section titles.
    static let section = ScaledFont.scaled(15, weight: .bold)
    /// Floating-panel labels and segmented controls.
    static let small = ScaledFont.scaled(12, weight: .semibold)
    /// Rows, labels and buttons.
    static let body = ScaledFont.scaled(13)
    /// Timers, sizes and zoom, in tabular figures.
    static let numbers = ScaledFont.scaled(13, weight: .bold, design: .monospaced, tabular: true)
    /// Keys in tooltips and hints.
    static let keycap = ScaledFont.scaled(11, design: .monospaced)

    static func title(_ size: CGFloat) -> ScaledFont { .scaled(size, weight: .bold) }
    /// File names in title bars and main buttons.
    static let label = ScaledFont.scaled(13, weight: .semibold)
    /// Notes under rows and key hints; pair it with `tertiaryText`.
    static let caption = ScaledFont.scaled(11)
    static let mono = numbers
    /// A toolbar button's symbol.
    static let toolIcon = ScaledFont.scaled(13, weight: .semibold)
    /// A section's small heading; use `sectionCaption()` for its tracking and colour too.
    static let sectionCaption = ScaledFont.scaled(11, weight: .semibold)

    /// How far content under an ink line stops short of its outer edge: under the line, so nothing bleeds past it, and a whole
    /// device pixel, because a fractional rounded clip leaves stray pixels at its corner. `scale` is the display's pixels per point.
    static func underInk(_ width: CGFloat, scale: CGFloat = 1) -> CGFloat { (width / 2 * scale).rounded(.up) / scale }

    /// An ink width on a whole number of device pixels, so a 1.5 pt line is 3 pixels on Retina and 2 on a 1x display
    /// instead of a grey half-pixel seam.
    static func inkWidth(_ width: CGFloat, scale: CGFloat = 1) -> CGFloat { max(1, (width * scale).rounded()) / scale }

    /// A shadow's offset on whole device pixels. Unlike a line, it can be zero: a pressed button's drop sinks to nothing.
    static func inkOffset(_ offset: CGFloat, scale: CGFloat = 1) -> CGFloat { (offset * scale).rounded() / scale }

    /// Ink faded for secondary text and icons. It's solid with Increase Contrast on, so the text holds its contrast over glass.
    static func faded(_ opacity: Double) -> ContrastAware {
        ContrastAware(standard: ink.opacity(opacity), increased: ink)
    }

    /// Ink faded for dividers and inactive marks. With Increase Contrast on it's at least 60%, about 4.9:1 on white, so
    /// it clears the 3:1 that lines and marks need without weighing as much as an ink border.
    static func faint(_ opacity: Double) -> ContrastAware {
        ContrastAware(standard: ink.opacity(opacity), increased: ink.opacity(max(opacity, 0.6)))
    }
}

extension EnvironmentValues {
    /// Settings › General › Text size, set at the root of every hosted view.
    @Entry var textSize = TextSize.standard
}

/// A system font that grows with Settings › General › Text size. Use `.font(.scaled(…))` for Shot's own interface text;
/// a plain `Font` stays the size it says, for anything that shows content, such as an annotation's text.
struct ScaledFont {
    let size: CGFloat
    var weight: Font.Weight?
    var design: Font.Design?
    /// Fixed-width digits, so a ticking number doesn't shift its neighbours.
    var tabular = false

    static func scaled(_ size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil, tabular: Bool = false) -> ScaledFont {
        ScaledFont(size: size, weight: weight, design: design, tabular: tabular)
    }

    func resolved(_ textSize: TextSize) -> Font {
        let font = Font.system(size: textSize.points(size), weight: weight, design: design)
        return tabular ? font.monospacedDigit() : font
    }

    /// For AppKit drawing, which can't read the environment.
    func points(_ textSize: TextSize) -> CGFloat { textSize.points(size) }
}

private struct ScaledFontModifier: ViewModifier {
    let font: ScaledFont
    @Environment(\.textSize) private var textSize

    func body(content: Content) -> some View {
        content.font(font.resolved(textSize))
    }
}

extension View {
    func font(_ font: ScaledFont) -> some View {
        modifier(ScaledFontModifier(font: font))
    }
}

/// A colour that steps up to `increased` while Increase Contrast is on.
struct ContrastAware: ShapeStyle {
    let standard: Color
    let increased: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorSchemeContrast == .increased ? increased : standard
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// A colour that follows the view's appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

/// Lays out content over `fill` in the light appearance when the fill is light and mostly opaque, such as an accent colour,
/// so its `ink` stays dark in dark mode. Over `paper`, glass or a dark fill, content keeps the appearance it has.
private struct InkOnFill: ViewModifier {
    let fill: Color?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, scheme)
    }

    private var scheme: ColorScheme {
        guard colorScheme == .dark, let fill else { return colorScheme }
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let color = fill.resolve(in: environment)
        // Above 0.18, near-black ink has more contrast on the fill than near-white ink does.
        let luminance = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        return color.opacity >= 0.5 && luminance > 0.18 ? .light : .dark
    }
}

extension View {
    /// For content drawn straight over a fill rather than through `brutalSurface`, such as a selected segment.
    func inkOnFill(_ fill: Color?) -> some View {
        modifier(InkOnFill(fill: fill))
    }
}

// MARK: Surfaces

/// The border and hard shadow as one filled path: the shape swept along the shadow's diagonal, minus its interior. Filling it
/// once anti-aliases every edge once; a stroke over separate shadow copies stacks soft edge pixels into seams and stair-steps.
/// The interior stays open, so translucent glass never shows the shadow through itself.
private struct InkOutline<S: InsettableShape>: Shape {
    let shape: S
    let border: CGFloat
    let shadow: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = shape.path(in: rect)
        // Half-point steps: the union's scallops between copies are far below a pixel.
        let steps = Int(shadow * 2)
        let swept = steps == 0 ? body : (1...steps).reduce(body) { outline, step in
            let distance = shadow * CGFloat(step) / CGFloat(steps)
            return outline.union(body.offsetBy(dx: distance, dy: distance))
        }
        return swept.subtracting(shape.inset(by: border).path(in: rect))
    }
}

struct BrutalSurface<S: InsettableShape, Fill: ShapeStyle>: ViewModifier {
    let shape: S
    let fill: Fill
    var glass = false
    var shadow = Brutal.shadow
    var border = Brutal.border
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var scale

    func body(content: Content) -> some View {
        let border = Brutal.inkWidth(border, scale: scale)
        let shadow = Brutal.inkOffset(shadow, scale: scale)
        return content
            .inkOnFill(fill as? Color)
            .background {
                ZStack {
                    // Over a material, glass turns solid with Increase Contrast on so text over it holds its contrast.
                    if glass, contrast == .increased {
                        shape.inset(by: Brutal.underInk(border, scale: scale)).fill(Brutal.group)
                    } else if glass {
                        shape.inset(by: Brutal.underInk(border, scale: scale)).fill(.ultraThinMaterial)
                    }
                    shape.inset(by: Brutal.underInk(border, scale: scale)).fill(fill)
                }
            }
            .overlay(InkOutline(shape: shape, border: border, shadow: shadow).fill(Brutal.line))
    }
}

/// The Rest, Group and Float levels from the spec. In dark, Rest is a 0.5 pt edge with a darker shadow.
private struct DepthSurface<Fill: ShapeStyle>: ViewModifier {
    let level: Brutal.Depth
    let fill: Fill
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        let dark = colorScheme == .dark
        let ink = Color(hex: 0x16161A)
        content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(edge, lineWidth: edgeWidth(dark)))
            .shadow(color: shadow(dark, ink: ink).color, radius: shadow(dark, ink: ink).blur / 2, y: shadow(dark, ink: ink).y)
    }

    private var edge: Color {
        switch level {
        case .rest: Brutal.controlEdge
        case .group: Brutal.hairline
        case .float: Color(light: .black.opacity(0.2), dark: .white.opacity(0.14))
        }
    }

    private func edgeWidth(_ dark: Bool) -> CGFloat {
        switch level {
        case .rest: dark ? 0.5 : 1
        case .group: 1
        case .float: 0.5
        }
    }

    private func shadow(_ dark: Bool, ink: Color) -> (color: Color, blur: CGFloat, y: CGFloat) {
        switch level {
        case .rest: (dark ? .black.opacity(0.3) : ink.opacity(0.06), 1, 1)
        case .group: (dark ? .black.opacity(0.3) : ink.opacity(0.04), 2, 1)
        case .float: (dark ? .black.opacity(0.45) : ink.opacity(0.16), 24, 8)
        }
    }
}

extension View {
    func brutalSurface<Fill: ShapeStyle>(_ fill: Fill, glass: Bool = false, radius: CGFloat = Brutal.radius, shadow: CGFloat = Brutal.shadow, border: CGFloat = Brutal.border) -> some View {
        modifier(BrutalSurface(shape: RoundedRectangle(cornerRadius: radius, style: .circular), fill: fill, glass: glass, shadow: shadow, border: border))
    }

    /// Round variant; a circular-cornered rounded rectangle at half its size is not a true circle.
    func brutalCircle<Fill: ShapeStyle>(_ fill: Fill, shadow: CGFloat = Brutal.shadow) -> some View {
        modifier(BrutalSurface(shape: Circle(), fill: fill, shadow: shadow))
    }

    func glassCard() -> some View {
        brutalSurface(Brutal.glass, glass: true)
    }

    /// A rest, group or float surface: the quiet depths, with no ink outline. `fill` is the surface's colour.
    func depth<Fill: ShapeStyle>(_ level: Brutal.Depth, fill: Fill, radius: CGFloat = Brutal.Radius.group) -> some View {
        modifier(DepthSurface(level: level, fill: fill, radius: radius))
    }

    /// A section's small capitals heading, as the image picker and the video crop bar have.
    func sectionCaption() -> some View {
        font(Brutal.sectionCaption).tracking(1.2).foregroundStyle(Brutal.faded(0.75))
    }

    /// An ink border with the content stopping under the line, so no colour bleeds through its anti-aliased outer edge.
    /// `dash` draws it as dashes, as `StrokeStyle` takes them.
    func inkBorder<S: InsettableShape>(_ shape: S, width: CGFloat, color: Color = Brutal.line, dash: [CGFloat] = []) -> some View {
        modifier(InkBorder(shape: shape, width: width, color: color, dash: dash))
    }
}

/// `inkBorder`'s modifier. It reads the display's scale so the line lands on whole device pixels.
private struct InkBorder<S: InsettableShape>: ViewModifier {
    let shape: S
    let width: CGFloat
    let color: Color
    let dash: [CGFloat]
    @Environment(\.displayScale) private var scale

    func body(content: Content) -> some View {
        let width = Brutal.inkWidth(width, scale: scale)
        content
            .clipShape(shape.inset(by: Brutal.underInk(width, scale: scale)))
            .overlay(shape.strokeBorder(color, style: StrokeStyle(lineWidth: width, dash: dash)))
    }
}

// MARK: Backdrop

/// The window's background: one solid, neutral surface, so the capture in it is the most colourful thing on screen.
struct GlassBackdrop: View {
    var body: some View {
        Brutal.window
    }
}

// MARK: Controls

/// Shot's buttons, from Components › Buttons. A screen or panel has at most one ink button, `.main`: the action you'll
/// take next, such as Copy, Save, Record, Stop or Continue. Every other button is `.secondary`, `.plain` or `.toolbar`.
struct BrutalButtonStyle: PrimitiveButtonStyle {
    enum Kind {
        /// The one ink button per screen: accent fill, 1.5 pt ink outline and a 2 pt drop it sinks into when pressed.
        case main
        /// A white button at the Rest depth, like a native bordered button.
        case secondary
        /// A pop-up menu's button: the secondary look, tighter, for `BrutalPopUp`.
        case popUp
        /// Text only, in accent text.
        case plain
        /// Borderless, for toolbars and bars. It fills on hover, and while `isOn`, for a panel or option that's showing.
        case toolbar
        /// A toolbar button that picks a tool. The selected tool (`isOn`) is drawn in ink, like `main`, with a 1.5 pt drop.
        case tool
    }

    var kind: Kind
    /// A toolbar toggle that's on, or the selected tool.
    var isOn: Bool
    /// Red: a red ink button for `main`, red text and edge for the others.
    var destructive: Bool
    /// For the dark floating panels: black ink, group corners, and white text and icons.
    var floating: Bool
    /// Onboarding and dialogs, with more room around the title.
    var large: Bool

    init(_ kind: Kind = .secondary, isOn: Bool = false, destructive: Bool = false, floating: Bool = false, large: Bool = false) {
        self.kind = kind
        self.isOn = isOn
        self.destructive = destructive
        self.floating = floating
        self.large = large
    }

    func makeBody(configuration: Configuration) -> some View {
        BrutalButtonFocus(style: self, configuration: configuration)
    }
}

/// Swaps the system's blue focus ring for the accent halo. A `ButtonStyle` can't see whether its button has keyboard
/// focus, so this wraps the button and tracks it.
private struct BrutalButtonFocus: View {
    let style: BrutalButtonStyle
    let configuration: PrimitiveButtonStyleConfiguration
    @FocusState private var focused: Bool

    var body: some View {
        Button(configuration)
            .buttonStyle(BrutalButtonLook(style: style, focused: focused))
            .focusEffectDisabled()
            .focused($focused)
    }
}

private struct BrutalButtonLook: ButtonStyle {
    let style: BrutalButtonStyle
    let focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        BrutalButtonBody(style: style, label: configuration.label, pressed: configuration.isPressed, isFocused: focused)
    }
}

/// `BrutalButtonStyle`'s view, which reads hover and the accessibility settings.
private struct BrutalButtonBody: View {
    let style: BrutalButtonStyle
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var scale
    @State private var hovering = false

    /// Text on the accent stays near-black in both appearances.
    private static let onAccent = Color(hex: 0x16161A)

    private var floating: Bool { style.floating }
    private var increased: Bool { contrast == .increased }

    /// Drawn in ink: the main button, or the selected tool. A disabled main button isn't the next action, so it draws as
    /// a disabled secondary one.
    private var inked: Bool {
        guard isEnabled else { return false }
        return style.kind == .main || (style.kind == .tool && style.isOn)
    }

    private var bordered: Bool { style.kind == .secondary || style.kind == .popUp || (style.kind == .main && !isEnabled) }
    private var borderless: Bool { style.kind == .toolbar || (style.kind == .tool && !inked) }
    private var toolbarSized: Bool { style.kind == .toolbar || style.kind == .tool }

    private var radius: CGFloat { floating ? Brutal.Radius.group : Brutal.Radius.control }
    private var inkColor: Color { floating ? .black : Brutal.line }
    private var drop: CGFloat { Brutal.inkOffset(style.kind == .tool ? 1.5 : 2, scale: scale) }
    /// Reduce Motion keeps the drop still and darkens the fill instead.
    private var sinks: Bool { inked && pressed && !reduceMotion }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        label
            .font(font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .opacity(style.kind == .plain && pressed ? 0.6 : 1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: toolbarSized ? (floating ? 36 : 30) : nil, minHeight: toolbarSized ? (floating ? 32 : 28) : nil)
            .background(fill, in: shape)
            .overlay {
                if pressed, style.kind != .plain, !sinks {
                    shape.fill(inked ? Brutal.line.opacity(0.12) : (floating ? Color.white.opacity(0.08) : Brutal.hover))
                }
            }
            .modifier(ButtonEdge(shape: shape, width: edgeWidth, color: edgeColor))
            .background {
                if inked {
                    shape.fill(inkColor).offset(y: sinks ? 0 : drop)
                }
            }
            .shadow(color: restShadow, radius: 0.5, y: 1)
            .offset(y: sinks ? drop : 0)
            .background {
                // A secondary button that's on, such as a shortcut recorder listening for keys, wears the focus halo too.
                if isEnabled, isFocused || (bordered && style.isOn) {
                    Color.clear
                        .inkBorder(RoundedRectangle(cornerRadius: radius + 4, style: .circular), width: 4, color: Brutal.focusRing)
                        .padding(-4)
                }
            }
            .environment(\.colorScheme, floating ? .dark : colorScheme)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(style.isOn ? .isSelected : [])
            .animation(Motion.animation(.press, reduceMotion: reduceMotion), value: pressed)
    }

    private var font: ScaledFont {
        switch style.kind {
        case .main: Brutal.label
        case .secondary, .popUp: Brutal.body
        case .plain: .scaled(13, weight: .medium)
        case .toolbar, .tool: .scaled(12, weight: .medium)
        }
    }

    private var horizontalPadding: CGFloat {
        switch style.kind {
        case .main, .secondary: style.large ? 20 : 14
        case .popUp: 9
        case .plain: 6
        case .toolbar, .tool: 7
        }
    }

    private var verticalPadding: CGFloat {
        switch style.kind {
        case .main, .secondary: floating ? 8 : (style.large ? 7 : 5)
        case .popUp: 3
        case .plain, .toolbar, .tool: 5
        }
    }

    private var fill: AnyShapeStyle {
        if inked {
            guard style.kind == .main, style.destructive else { return AnyShapeStyle(Brutal.accent) }
            // White on record red is under 4.5:1, so Increase Contrast darkens the red.
            return AnyShapeStyle(increased ? Color(hex: 0xC4271E) : Brutal.record)
        }
        if bordered {
            return AnyShapeStyle(floating ? Color.white.opacity(0.12) : Brutal.secondaryFill)
        }
        if borderless, isEnabled, style.isOn {
            return AnyShapeStyle(floating ? Color.white.opacity(0.16) : Brutal.hover)
        }
        if borderless, isEnabled, hovering {
            return AnyShapeStyle(Brutal.hover)
        }
        return AnyShapeStyle(Color.clear)
    }

    private var foreground: AnyShapeStyle {
        if !isEnabled {
            return AnyShapeStyle(floating ? Color.white.opacity(0.35) : Brutal.disabledText)
        }
        if inked {
            return AnyShapeStyle(style.kind == .main && style.destructive ? Color.white : Self.onAccent)
        }
        if style.destructive {
            return AnyShapeStyle(Brutal.destructiveText)
        }
        switch style.kind {
        case .main, .secondary, .popUp:
            return AnyShapeStyle(floating ? Color.white : Brutal.ink)
        case .plain:
            return floating ? AnyShapeStyle(Color.white.opacity(increased ? 1 : 0.8)) : AnyShapeStyle(Brutal.accentText)
        case .toolbar, .tool:
            if floating {
                return AnyShapeStyle(Color.white.opacity(style.isOn || increased ? 1 : 0.82))
            }
            return style.isOn ? AnyShapeStyle(Brutal.ink) : AnyShapeStyle(Brutal.faded(0.85))
        }
    }

    private var edgeWidth: CGFloat {
        if inked { return 1.5 }
        guard bordered, !floating else { return 0 }
        return colorScheme == .dark && !increased ? 0.5 : 1
    }

    /// The Rest edge, or the ink outline. Increase Contrast takes a secondary button's edge to at least 3:1.
    private var edgeColor: Color {
        if inked { return inkColor }
        if style.destructive, isEnabled { return Color(hex: 0xC4271E).opacity(increased ? 1 : 0.4) }
        if increased { return Brutal.ink.opacity(0.6) }
        return isEnabled ? Brutal.controlEdge : Brutal.hairline
    }

    private var restShadow: Color {
        guard bordered, isEnabled, !floating else { return .clear }
        return colorScheme == .dark ? .black.opacity(0.3) : Color(hex: 0x16161A).opacity(0.06)
    }
}

/// A button's edge, if it has one, drawn with `inkBorder` so it lands on whole device pixels.
private struct ButtonEdge<S: InsettableShape>: ViewModifier {
    let shape: S
    let width: CGFloat
    let color: Color

    func body(content: Content) -> some View {
        if width > 0 {
            content.inkBorder(shape, width: width, color: color)
        } else {
            content
        }
    }
}

// MARK: Choice

extension Brutal {
    /// The track behind a switch that's off, and a slider's unfilled part.
    static let quietTrack = Color(light: Color(hex: 0x16161A).opacity(0.12), dark: .white.opacity(0.16))
}

/// A switch, from Components › Choice. On, it's the accent with a 1.5 pt ink outline and an inked knob; off, a grey track
/// with a white knob. It draws the switch only, so put the label beside it and hide the toggle's own with `labelsHidden()`.
struct BrutalToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        BrutalSwitch(configuration: configuration)
    }
}

private struct BrutalSwitch: View {
    let configuration: ToggleStyleConfiguration
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            // Reduce Motion moves the knob at once.
            withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.82)) {
                configuration.isOn.toggle()
            }
        } label: {
            track
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focused)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }

    private var track: some View {
        let on = configuration.isOn
        let increased = contrast == .increased
        return ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Brutal.accent : Brutal.quietTrack)
            knob(on: on, increased: increased)
        }
        .frame(width: 38, height: 22)
        .modifier(ButtonEdge(shape: Capsule(), width: on ? 1.5 : (increased ? 1 : 0), color: on ? Brutal.line : Brutal.ink.opacity(0.6)))
        .background {
            if focused, isEnabled {
                Color.clear.inkBorder(Capsule(), width: 4, color: Brutal.focusRing).padding(-4)
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Capsule())
    }

    /// 17 pt inside the ink outline when on, 18 pt with a soft shadow when off.
    @ViewBuilder
    private func knob(on: Bool, increased: Bool) -> some View {
        if on {
            Circle().fill(.white)
                .inkBorder(Circle(), width: 1.5)
                .frame(width: 17, height: 17)
                .padding(2.5)
        } else {
            Circle().fill(.white)
                .modifier(ButtonEdge(shape: Circle(), width: increased ? 1 : 0, color: Color(hex: 0x16161A).opacity(0.6)))
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .padding(2)
        }
    }
}

/// A checkbox, from Components › Choice: a 16 pt box, the accent with a 1.5 pt ink inner edge and an ink tick when checked.
struct BrutalCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        BrutalCheckbox(configuration: configuration)
    }
}

private struct BrutalCheckbox: View {
    let configuration: ToggleStyleConfiguration
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                CheckboxMark(checked: configuration.isOn, focused: focused)
                configuration.label
                    .font(Brutal.body)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(Brutal.ink) : AnyShapeStyle(Brutal.disabledText))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focused)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}

/// The box a checkbox draws, for a control that isn't a `Toggle`, such as a gallery tile's selection box.
struct CheckboxMark: View {
    let checked: Bool
    var size: CGFloat = 16
    var focused = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size / 4, style: .circular)
        shape.fill(checked ? Brutal.accent : Brutal.secondaryFill)
            .overlay {
                if checked {
                    // The tick stays near-black on the accent in both appearances.
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.56, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x16161A))
                }
            }
            .inkBorder(shape, width: checked ? 1.5 : 1, color: edge)
            .shadow(color: checked ? .clear : (colorScheme == .dark ? .black.opacity(0.3) : Color(hex: 0x16161A).opacity(0.06)), radius: 0.5, y: 1)
            .frame(width: size, height: size)
            .background {
                if focused, isEnabled {
                    Color.clear.inkBorder(RoundedRectangle(cornerRadius: size / 4 + 4, style: .circular), width: 4, color: Brutal.focusRing).padding(-4)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
    }

    private var edge: Color {
        if checked { return Brutal.line }
        return contrast == .increased ? Brutal.ink.opacity(0.6) : Brutal.controlEdge
    }
}

/// A Mac segmented control: a quiet white thumb on a field-fill track, with no ink. Once focused, the arrow keys move the
/// selection, and VoiceOver reads it as a segmented control.
struct BrutalSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    /// Draws each segment as a picture instead of its label, given whether it's selected, in a segment `glyphSize` big.
    /// The label still names it to VoiceOver and in its tooltip.
    private var glyph: ((Value, Bool) -> AnyView)?
    private var glyphSize = CGSize(width: 26, height: 20)
    /// Whether the segments share all the width they're given, as the Style panel's Size does, rather than fit their labels.
    private var fills = false
    @Namespace private var thumb
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<Value>, options: [(value: Value, label: LocalizedStringResource)]) {
        self.init(selection: selection, options: options.map { ($0.value, String(localized: $0.label)) })
    }

    /// Options whose labels are already localized, such as a filter's titles.
    @_disfavoredOverload
    init<S: StringProtocol>(selection: Binding<Value>, options: [(value: Value, label: S)]) {
        _selection = selection
        self.options = options.map { ($0.value, String($0.label)) }
    }

    /// Segments drawn as pictures, such as the style bar's line widths, with labels that are already localized.
    init<Glyph: View>(selection: Binding<Value>, options: [(value: Value, label: String)], glyphSize: CGSize, @ViewBuilder glyph: @escaping (Value, Bool) -> Glyph) {
        _selection = selection
        self.options = options
        self.glyph = { AnyView(glyph($0, $1)) }
        self.glyphSize = glyphSize
    }

    private static var trackRadius: CGFloat { 8 }

    /// The segments share the whole width, each as wide as the others.
    func fillingWidth() -> Self {
        var copy = self
        copy.fills = true
        return copy
    }

    var body: some View {
        let track = RoundedRectangle(cornerRadius: Self.trackRadius, style: .circular)
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(2)
        .background(Brutal.fieldFill, in: track)
        .modifier(ButtonEdge(shape: track, width: contrast == .increased ? 1 : 0, color: Brutal.ink.opacity(0.6)))
        .opacity(isEnabled ? 1 : 0.5)
        .fixedSize(horizontal: !fills, vertical: true)
        .background {
            if focused, isEnabled {
                Color.clear.inkBorder(RoundedRectangle(cornerRadius: Self.trackRadius + 4, style: .circular), width: 4, color: Brutal.focusRing).padding(-4)
            }
        }
        .focusable(interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            step(by: press.key == .rightArrow ? 1 : -1)
            return .handled
        }
        .accessibilityRepresentation {
            Picker(selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].label).tag(options[index].value)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private func segment(_ option: (value: Value, label: String)) -> some View {
        if let glyph {
            let selected = option.value == selection
            glyph(option.value, selected)
                .frame(width: glyphSize.width, height: glyphSize.height)
                .background {
                    if selected {
                        SegmentThumb().matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { select(option.value) }
                .brutalTip(option.label)
        } else {
            textSegment(option)
        }
    }

    private func textSegment(_ option: (value: Value, label: String)) -> some View {
        let selected = option.value == selection
        return ZStack {
            // The semibold label holds each segment at its selected width, so picking one doesn't shift the others.
            Text(option.label).font(Brutal.small).hidden()
            Text(option.label)
                .font(selected ? Brutal.small : .scaled(12))
                .foregroundStyle(selected ? AnyShapeStyle(Brutal.ink) : AnyShapeStyle(ContrastAware(standard: Brutal.secondaryText, increased: Brutal.ink)))
        }
        .lineLimit(1)
        .padding(.horizontal, fills ? 4 : 12)
        .padding(.vertical, 3)
        .frame(maxWidth: fills ? .infinity : nil)
        .background {
            if selected {
                SegmentThumb().matchedGeometryEffect(id: "thumb", in: thumb)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { select(option.value) }
    }

    private func select(_ value: Value) {
        guard isEnabled, value != selection else {
            return
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.86)) {
            selection = value
        }
    }

    private func step(by offset: Int) {
        guard let index = options.firstIndex(where: { $0.value == selection }) else {
            return
        }
        let next = min(max(index + offset, 0), options.count - 1)
        select(options[next].value)
    }
}

/// The selected segment: white in light with a soft shadow and a faint edge, `#4A4A50` in dark.
private struct SegmentThumb: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.control, style: .circular)
        let dark = colorScheme == .dark
        shape.fill(Brutal.selectedSegment)
            .modifier(ButtonEdge(shape: shape, width: contrast == .increased ? 1 : (dark ? 0 : 0.5), color: contrast == .increased ? Brutal.ink.opacity(0.6) : Color(hex: 0x16161A).opacity(0.12)))
            .shadow(color: dark ? .black.opacity(0.3) : Color(hex: 0x16161A).opacity(0.14), radius: 1, y: 1)
    }
}

// MARK: Layout

extension EnvironmentValues {
    /// What's typed in the Settings sidebar's search. Rows that don't match it hide, and groups with no rows left hide too.
    @Entry var settingsQuery = ""
    /// The names of the section and group a Settings row sits in, which its search also matches.
    @Entry var settingsContext: [String] = []
}

/// A Settings group's name, 12 pt in, over its panel or preview.
struct SettingsGroupHeading: View {
    let title: String

    init(_ title: LocalizedStringResource) {
        self.title = String(localized: title)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S) {
        self.title = String(title)
    }

    var body: some View {
        Text(title)
            .font(.scaled(12, weight: .semibold))
            .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
            .padding(.leading, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A group of Settings rows: its name, if it has one, over a grouped panel, with a separator between rows, and an optional
/// note under the panel. While searching, it shows only the rows that match, without the note, and nothing when no row does.
struct SettingsCard<Content: View>: View {
    var title: LocalizedStringResource?
    var note: LocalizedStringResource?
    @ViewBuilder let content: Content
    @Environment(\.settingsContext) private var context
    @Environment(\.settingsQuery) private var query

    var body: some View {
        let heading = title.map { String(localized: $0) }
        Group(subviews: content) { rows in
            if let first = rows.first {
                VStack(alignment: .leading, spacing: 6) {
                    if let heading {
                        SettingsGroupHeading(heading)
                    }
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            if row.id != first.id {
                                Brutal.separator.frame(height: 1)
                            }
                            row
                        }
                    }
                    .depth(.group, fill: Brutal.group, radius: Brutal.Radius.group)
                    if let note, SettingsSearch.terms(query).isEmpty {
                        Text(note)
                            .font(Brutal.caption)
                            .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.settingsContext, context + (heading.map { [$0] } ?? []))
    }
}

/// A Settings row: an optional icon, its name and an optional description on the left, its control on the right. It hides
/// while a search doesn't match its name, description, group or section.
struct SettingRow<Control: View>: View {
    /// A 16 pt line icon before the name, 12 pt from it, as Settings › Shortcuts gives each action.
    struct Icon {
        let symbol: String
        var tint: Color = Brutal.ink.opacity(0.85)
    }

    let title: String
    var subtitle: String?
    var icon: Icon?
    @ViewBuilder let control: Control
    @Environment(\.settingsQuery) private var query
    @Environment(\.settingsContext) private var context

    init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, @ViewBuilder control: () -> Control) {
        self.init(title: String(localized: title), subtitle: subtitle.map { String(localized: $0) }, control: control)
    }

    /// A row whose title is already localized, such as an action's.
    @_disfavoredOverload
    init<S: StringProtocol>(title: S, subtitle: String? = nil, icon: Icon? = nil, @ViewBuilder control: () -> Control) {
        self.title = String(title)
        self.subtitle = subtitle
        self.icon = icon
        self.control = control()
    }

    var body: some View {
        if SettingsSearch.matches(query, in: context + [title, subtitle ?? ""]) {
            HStack(alignment: .center, spacing: 16) {
                if let icon {
                    Image(systemName: icon.symbol)
                        .font(.scaled(14, weight: .medium))
                        .foregroundStyle(icon.tint)
                        .frame(width: 16)
                        .padding(.trailing, -4)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Brutal.body).foregroundStyle(Brutal.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(Brutal.caption)
                            .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
        }
    }
}

struct ToggleRow: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) {
            Toggle(String(localized: title), isOn: $isOn).toggleStyle(BrutalToggleStyle()).labelsHidden()
                .accessibilityLabel(Text(title))
        }
    }
}

extension View {
    /// Settings content that isn't a row, such as a preview or a note, which hides while searching.
    func hiddenWhileSearching() -> some View {
        modifier(HiddenWhileSearching())
    }
}

private struct HiddenWhileSearching: ViewModifier {
    @Environment(\.settingsQuery) private var query

    func body(content: Content) -> some View {
        if SettingsSearch.terms(query).isEmpty {
            content
        }
    }
}
