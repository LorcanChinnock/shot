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

    /// Edges of groups and cards.
    static let hairline = Color(light: Color(hex: 0x16161A).opacity(0.08), dark: .white.opacity(0.08))
    /// Edges of buttons and pop-up menus.
    static let controlEdge = Color(light: Color(hex: 0x16161A).opacity(0.14), dark: .white.opacity(0.12))
    /// Rows inside a group.
    static let separator = Color(light: Color(hex: 0x16161A).opacity(0.07), dark: .white.opacity(0.08))
    /// Search fields, segmented tracks and tag chips.
    static let fieldFill = Color(light: Color(hex: 0x16161A).opacity(0.06), dark: .white.opacity(0.07))
    /// Toolbar buttons on hover.
    static let hover = Color(light: Color(hex: 0x16161A).opacity(0.07), dark: .white.opacity(0.08))

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

    /// A section's small capitals heading, as the Style popover and the video inspector have.
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

struct BrutalButtonStyle: ButtonStyle {
    var color: Color = Brutal.paper
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.scaled(compact ? 12 : 13, weight: .bold))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .brutalSurface(color, radius: Brutal.Radius.button, shadow: pressed ? 0 : 3)
            .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(response: 0.15, dampingFraction: 0.7), value: pressed)
            .contentShape(Rectangle())
    }
}

struct BrutalToggleStyle: ToggleStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Color.clear
                    .frame(width: 48, height: 28)
                Brutal.knob
                    .inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular), width: 2)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 6)
            }
            .brutalSurface(configuration.isOn ? color : Brutal.well, radius: Brutal.Radius.inset, shadow: 2)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
    }
}

struct BrutalSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var color: Color

    init(selection: Binding<Value>, options: [(value: Value, label: LocalizedStringResource)], color: Color) {
        self.init(selection: selection, options: options.map { ($0.value, String(localized: $0.label)) }, color: color)
    }

    /// Options whose labels are already localized, such as a filter's titles.
    @_disfavoredOverload
    init<S: StringProtocol>(selection: Binding<Value>, options: [(value: Value, label: S)], color: Color) {
        _selection = selection
        self.options = options.map { ($0.value, String($0.label)) }
        self.color = color
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.scaled(12, weight: selected ? .heavy : .semibold))
                        .foregroundStyle(Brutal.faded(selected ? 1 : 0.65))
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .inkOnFill(selected ? color : nil)
                        .background(selected ? color : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    Rectangle().fill(Brutal.line).frame(width: 2)
                }
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: Brutal.Radius.button, style: .circular).inset(by: Brutal.underInk(Brutal.border)))
        .brutalSurface(Brutal.well, radius: Brutal.Radius.button, shadow: 2)
    }
}

struct BrutalChip: View {
    let text: String
    var color: Color = Brutal.paper

    init(text: LocalizedStringResource, color: Color = Brutal.paper) {
        self.init(text: String(localized: text), color: color)
    }

    /// A chip whose text is already localized, or is a number or name.
    @_disfavoredOverload
    init<S: StringProtocol>(text: S, color: Color = Brutal.paper) {
        self.text = String(text)
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.scaled(11, weight: .heavy))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .brutalSurface(color, radius: Brutal.Radius.chip, shadow: 2)
    }
}

// MARK: Layout

struct SettingsCard<Content: View>: View {
    let title: LocalizedStringResource
    var symbol: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.scaled(11, weight: .bold))
                }
                Text(String(localized: title).uppercased()).font(Brutal.sectionCaption).tracking(1.2)
            }
            .foregroundStyle(Brutal.faded(0.75))
            .padding(.bottom, 6)
            VStack(spacing: 0) {
                content
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    var divider = true
    @ViewBuilder let control: Control

    init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, divider: Bool = true, @ViewBuilder control: () -> Control) {
        self.init(title: String(localized: title), subtitle: subtitle.map { String(localized: $0) }, divider: divider, control: control)
    }

    /// A row whose title is already localized, such as an action's.
    @_disfavoredOverload
    init<S: StringProtocol>(title: S, subtitle: String? = nil, divider: Bool = true, @ViewBuilder control: () -> Control) {
        self.title = String(title)
        self.subtitle = subtitle
        self.divider = divider
        self.control = control()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Brutal.label).foregroundStyle(Brutal.ink)
                    if let subtitle {
                        Text(subtitle).font(Brutal.caption).foregroundStyle(Brutal.faded(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control
            }
            .padding(.vertical, 9)
            if divider {
                Rectangle().fill(Brutal.faint(0.12)).frame(height: 1.5)
            }
        }
    }
}

struct ToggleRow: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @Binding var isOn: Bool
    var color: Color
    var divider = true

    var body: some View {
        SettingRow(title: title, subtitle: subtitle, divider: divider) {
            Toggle(String(localized: title), isOn: $isOn).toggleStyle(BrutalToggleStyle(color: color)).labelsHidden()
                .accessibilityLabel(Text(title))
        }
    }
}
