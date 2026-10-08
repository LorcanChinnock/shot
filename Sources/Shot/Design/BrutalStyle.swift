import AppKit
import SwiftUI

/// Design tokens and components for the glass × neo-brutalist settings UI.
enum Brutal {
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.10)
    static let border: CGFloat = 3
    static let radius: CGFloat = 12
    static let shadow: CGFloat = 4

    // Spacing rule: keep at least `minGap` of clear space between any two ink lines, shadows included.
    static let minGap: CGFloat = 6
    /// Content inset from the window border.
    static let windowInset: CGFloat = 24
    /// Inset inside a bordered group that holds other bordered controls.
    static let groupInset: CGFloat = 7
    static let sectionGap: CGFloat = 16

    static let yellow = Color(hex: 0xFFD43B)
    static let pink = Color(hex: 0xFF7AB6)
    static let mint = Color(hex: 0x4FE3B5)
    static let sky = Color(hex: 0x6FC3FF)
    static let violet = Color(hex: 0x9B8CFF)
    static let red = Color(hex: 0xFF5C5C)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }
    static let label = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11.5, weight: .medium)
    static let mono = Font.system(size: 12, weight: .bold, design: .monospaced)

    /// How far content under an ink line stops short of its outer edge: under the line, so nothing bleeds past it, and a whole
    /// point, because a fractional rounded clip leaves stray pixels at its corner on 1x displays.
    static func underInk(_ width: CGFloat) -> CGFloat { (width / 2).rounded(.up) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
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

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if glass {
                        shape.inset(by: Brutal.underInk(border)).fill(.ultraThinMaterial)
                    }
                    shape.inset(by: Brutal.underInk(border)).fill(fill)
                }
            }
            .overlay(InkOutline(shape: shape, border: border, shadow: shadow).fill(Brutal.ink))
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
        brutalSurface(Color.white.opacity(0.42), glass: true)
    }

    /// An ink border with the content stopping under the line, so no colour bleeds through its anti-aliased outer edge.
    /// `dash` draws it as dashes, as `StrokeStyle` takes them.
    func inkBorder<S: InsettableShape>(_ shape: S, width: CGFloat, color: Color = Brutal.ink, dash: [CGFloat] = []) -> some View {
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

    var body: some View {
        ZStack {
            VisualEffectBackground()
            Color.white.opacity(0.35)
            TimelineView(.animation(paused: reduceMotion || activeState == .inactive)) { timeline in
                blobLayer(at: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
            }
            dotGrid
        }
    }

    private func blobLayer(at time: Double) -> some View {
        Canvas { ctx, size in
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
                    .init(color: blob.color.opacity(blob.opacity), location: 0),
                    .init(color: blob.color.opacity(blob.opacity * 0.5), location: 0.45),
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
    var color: Color = .white
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .bold))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .brutalSurface(color, radius: 8, shadow: pressed ? 0 : 3)
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
                Color.white
                    .inkBorder(RoundedRectangle(cornerRadius: 4, style: .circular), width: 2)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 6)
            }
            .brutalSurface(configuration.isOn ? color : Color.white.opacity(0.7), radius: 7, shadow: 2)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
    }
}

struct BrutalSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var color: Color

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
                        .font(.system(size: 12, weight: selected ? .heavy : .semibold))
                        .foregroundStyle(Brutal.ink.opacity(selected ? 1 : 0.65))
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(selected ? color : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    Rectangle().fill(Brutal.ink).frame(width: 2)
                }
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .circular).inset(by: Brutal.underInk(Brutal.border)))
        .brutalSurface(Color.white.opacity(0.7), radius: 8, shadow: 2)
    }
}

struct BrutalChip: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .brutalSurface(color, radius: 6, shadow: 2)
    }
}

// MARK: Layout

struct SettingsCard<Content: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                }
                Text(title.uppercased()).font(.system(size: 11, weight: .black)).tracking(1.2)
            }
            .foregroundStyle(Brutal.ink.opacity(0.75))
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Brutal.label).foregroundStyle(Brutal.ink)
                    if let subtitle {
                        Text(subtitle).font(Brutal.caption).foregroundStyle(Brutal.ink.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control
            }
            .padding(.vertical, 9)
            if divider {
                Rectangle().fill(Brutal.ink.opacity(0.12)).frame(height: 1.5)
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var color: Color
    var divider = true

    var body: some View {
        SettingRow(title: title, subtitle: subtitle, divider: divider) {
            Toggle(title, isOn: $isOn).toggleStyle(BrutalToggleStyle(color: color)).labelsHidden()
                .accessibilityLabel(Text(title))
        }
    }
}
