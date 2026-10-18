import AppKit
import ShotCoreApple
import SwiftUI

/// Design tokens and components for the glass × neo-brutalist settings UI.
enum Brutal {
    // Dark mode keeps black lines and hard shadows, and shows depth by lightness instead: the backdrop is darkest, glass cards
    // sit a step lighter, and `paper` (buttons, menus, chips) lighter still. Text is the only light element, a soft off-white
    // rather than white, and the accents lose a little saturation so they don't glare on dark.

    /// Text and marks on `paper` or glass: near-black in light mode, off-white in dark. Text on an accent fill stays near-black
    /// either way, because a surface with a light fill lays out its content in the light appearance.
    static let ink = Color(light: Color(red: 0.07, green: 0.07, blue: 0.10), dark: Color(hex: 0xE6E3DC))
    /// Borders and hard shadows: near-black in both appearances.
    static let line = Color(light: Color(red: 0.07, green: 0.07, blue: 0.10), dark: Color(hex: 0x050507))
    /// The neutral fill under ink: buttons, chips, menus and floating panels. White in light mode, a raised grey in dark.
    static let paper = Color(light: .white, dark: Color(hex: 0x38373E))
    /// A glass card's tint.
    static let glass = Color(light: .white.opacity(0.42), dark: Color(hex: 0x2C2B31).opacity(0.9))
    /// A recessed fill below `paper`: a toggle that's off, a segmented control's track, an unlit meter bar.
    static let well = Color(light: .white.opacity(0.7), dark: Color(hex: 0x1F1E23))
    /// A toggle's knob while it's off.
    static let knob = Color(light: .white, dark: Color(hex: 0x8E8B93))
    /// `ink`, `yellow` and `red` for AppKit drawing, in their light-mode colours, for marks drawn over a capture or the screen.
    /// `inkNS` is also `line` in either appearance. Chrome that follows the appearance uses `NSColor(Brutal.paper)` and friends.
    static var inkNS: NSColor { NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1) }
    static var yellowNS: NSColor { NSColor(srgbRed: 1, green: 0xD4 / 255, blue: 0x3B / 255, alpha: 1) }
    static var redNS: NSColor { NSColor(srgbRed: 1, green: 0x5C / 255, blue: 0x5C / 255, alpha: 1) }
    static let border: CGFloat = 3
    static let radius: CGFloat = 12
    static let shadow: CGFloat = 4

    /// Corner radii smaller than `radius`, by what they round.
    enum Radius {
        /// Timeline clips and thumbnails.
        static let tiny: CGFloat = 4
        /// Chips and small buttons.
        static let chip: CGFloat = 6
        /// Options inside a bordered group, such as segments, tiles and layer rows, which sit `groupInset` in.
        static let inset: CGFloat = 7
        /// Buttons and cards.
        static let button: CGFloat = 8
        /// Floating panels: toasts, popovers and menus.
        static let panel: CGFloat = 10
    }

    // Spacing rule: keep at least `minGap` of clear space between any two ink lines, shadows included.
    static let minGap: CGFloat = 6
    /// Content inset from the window border.
    static let windowInset: CGFloat = 24
    /// Inset inside a bordered group that holds other bordered controls.
    static let groupInset: CGFloat = 7
    static let sectionGap: CGFloat = 16

    static let yellow = Color(light: Color(hex: 0xFFD43B), dark: Color(hex: 0xEDCB55))
    static let pink = Color(light: Color(hex: 0xFF7AB6), dark: Color(hex: 0xE58BB3))
    static let mint = Color(light: Color(hex: 0x4FE3B5), dark: Color(hex: 0x62CDAB))
    static let sky = Color(light: Color(hex: 0x6FC3FF), dark: Color(hex: 0x80BBE6))
    static let violet = Color(light: Color(hex: 0x9B8CFF), dark: Color(hex: 0x9C92E3))
    static let red = Color(light: Color(hex: 0xFF5C5C), dark: Color(hex: 0xE26C6C))
    static let orange = Color(light: Color(hex: 0xFF9F43), dark: Color(hex: 0xE8A060))
    static let lime = Color(light: Color(hex: 0xB6E24B), dark: Color(hex: 0xB1CF62))

    static func title(_ size: CGFloat) -> ScaledFont { .scaled(size, weight: .black) }
    static let label = ScaledFont.scaled(13, weight: .semibold)
    static let caption = ScaledFont.scaled(11.5, weight: .medium)
    static let mono = ScaledFont.scaled(12, weight: .bold, design: .monospaced)
    /// A toolbar button's symbol.
    static let toolIcon = ScaledFont.scaled(13, weight: .bold)
    /// A section's small capitals heading; use `sectionCaption()` for its tracking and colour too.
    static let sectionCaption = ScaledFont.scaled(11, weight: .black)

    /// How far content under an ink line stops short of its outer edge: under the line, so nothing bleeds past it, and a whole
    /// point, because a fractional rounded clip leaves stray pixels at its corner on 1x displays.
    static func underInk(_ width: CGFloat) -> CGFloat { (width / 2).rounded(.up) }

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

    static func scaled(_ size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> ScaledFont {
        ScaledFont(size: size, weight: weight, design: design)
    }

    func resolved(_ textSize: TextSize) -> Font {
        .system(size: textSize.points(size), weight: weight, design: design)
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

    func body(content: Content) -> some View {
        content
            .inkOnFill(fill as? Color)
            .background {
                ZStack {
                    // With Increase Contrast on, glass turns nearly opaque so text over it holds its contrast.
                    if glass, contrast == .increased {
                        shape.inset(by: Brutal.underInk(border)).fill(Color(light: .white.opacity(0.9), dark: Color(hex: 0x2C2B31).opacity(0.97)))
                    } else if glass {
                        shape.inset(by: Brutal.underInk(border)).fill(.ultraThinMaterial)
                    }
                    shape.inset(by: Brutal.underInk(border)).fill(fill)
                }
            }
            .overlay(InkOutline(shape: shape, border: border, shadow: shadow).fill(Brutal.line))
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

    /// A section's small capitals heading, as the Style popover and the video inspector have.
    func sectionCaption() -> some View {
        font(Brutal.sectionCaption).tracking(1.2).foregroundStyle(Brutal.faded(0.75))
    }

    /// An ink border with the content stopping under the line, so no colour bleeds through its anti-aliased outer edge.
    /// `dash` draws it as dashes, as `StrokeStyle` takes them.
    func inkBorder<S: InsettableShape>(_ shape: S, width: CGFloat, color: Color = Brutal.line, dash: [CGFloat] = []) -> some View {
        clipShape(shape.inset(by: Brutal.underInk(width))).overlay(shape.strokeBorder(color, style: StrokeStyle(lineWidth: width, dash: dash)))
    }
}

// MARK: Backdrop

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Frosted window backdrop: blurred desktop, soft color blobs drifting slowly, and a faint dot grid.
struct GlassBackdrop: View {
    /// Positions and sizes are fractions of the window, so the composition holds at any window or display size.
    private struct Blob {
        let color: Color
        let anchor: CGPoint
        let size: CGFloat
        let opacity: Double
        let drift: CGFloat
        let period: Double
        let phase: Double
    }

    private static let blobs = [
        Blob(color: Brutal.pink, anchor: CGPoint(x: 0.12, y: 0.15), size: 0.5, opacity: 0.55, drift: 0.08, period: 31, phase: 0),
        Blob(color: Brutal.sky, anchor: CGPoint(x: 0.9, y: 0.88), size: 0.55, opacity: 0.55, drift: 0.09, period: 37, phase: 2),
        Blob(color: Brutal.yellow, anchor: CGPoint(x: 0.85, y: 0.1), size: 0.4, opacity: 0.5, drift: 0.07, period: 43, phase: 4),
        Blob(color: Brutal.mint, anchor: CGPoint(x: 0.15, y: 0.9), size: 0.36, opacity: 0.45, drift: 0.07, period: 29, phase: 5),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VisualEffectBackground()
            // With Increase Contrast on, the blobs go and the frost turns nearly opaque, so text keeps a plain, solid backing.
            if contrast == .increased {
                Color(light: .white.opacity(0.9), dark: Color(hex: 0x17161B).opacity(0.97))
            } else {
                Color(light: .white.opacity(0.35), dark: Color(hex: 0x17161B).opacity(0.85))
                TimelineView(.animation(paused: reduceMotion || activeState == .inactive)) { timeline in
                    blobLayer(at: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            dotGrid
        }
    }

    private func blobLayer(at time: Double) -> some View {
        // On dark, full-strength blobs glow; a third of the strength keeps the colour without the glare.
        let strength = colorScheme == .dark ? 0.36 : 1
        return Canvas { ctx, size in
            let reach = max(size.width, size.height)
            for blob in Self.blobs {
                let angle = time / blob.period * 2 * .pi + blob.phase
                let breathing = 1 + 0.08 * sin(angle * 1.7)
                let diameter = reach * blob.size * breathing
                let center = CGPoint(
                    x: size.width * blob.anchor.x + reach * blob.drift * cos(angle),
                    y: size.height * blob.anchor.y + reach * blob.drift * sin(angle * 0.8)
                )
                let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
                let gradient = Gradient(stops: [
                    .init(color: blob.color.opacity(blob.opacity * strength), location: 0),
                    .init(color: blob.color.opacity(blob.opacity * strength * 0.5), location: 0.45),
                    .init(color: blob.color.opacity(0), location: 1),
                ])
                ctx.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: diameter / 2)
                )
            }
        }
    }

    /// Strongest at the centre, fading out toward the edges.
    private var dotGrid: some View {
        Canvas { ctx, size in
            let step: CGFloat = 18
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            let farthest = hypot(middle.x, middle.y)
            for x in stride(from: step / 2, to: size.width, by: step) {
                for y in stride(from: step / 2, to: size.height, by: step) {
                    let falloff = 1 - 0.7 * hypot(x - middle.x, y - middle.y) / farthest
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(Brutal.ink.opacity(0.10 * falloff)))
                }
            }
        }
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
