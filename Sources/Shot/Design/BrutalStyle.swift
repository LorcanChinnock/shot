import AppKit
import SwiftUI

/// Design tokens and components for the glass × neo-brutalist settings UI.
enum Brutal {
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.10)
    static let border: CGFloat = 2.5
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
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: Surfaces

/// A copy of `shape` swept along the offset diagonal with the card's own interior knocked out, so translucent glass never shows it
/// through itself. The knockout stops inside the border, so the shadow runs fully under the opaque border;
/// stopping exactly at its inner edge leaves a hairline seam where both edges are anti-aliased.
private struct HardShadow<S: InsettableShape>: View {
    let shape: S
    let offset: CGFloat
    let border: CGFloat

    /// Copies of the shape along the diagonal, so the corners join the border instead of leaving a notch.
    private var sweepSteps: Int { max(Int(offset * 2), 1) }

    var body: some View {
        ZStack {
            ForEach(1...sweepSteps, id: \.self) { step in
                let distance = offset * CGFloat(step) / CGFloat(sweepSteps)
                shape.fill(Brutal.ink).offset(x: distance, y: distance)
            }
        }
            .mask {
                Rectangle().fill(.white)
                    .padding(-offset * 2)
                    .overlay(shape.inset(by: max(border - 1, 0)).fill(.black).blendMode(.destinationOut))
                    .compositingGroup()
            }
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
                        shape.inset(by: border / 2).fill(.ultraThinMaterial)
                    }
                    shape.inset(by: border / 2).fill(fill)
                }
            }
            .overlay(shape.strokeBorder(Brutal.ink, lineWidth: border))
            .background(HardShadow(shape: shape, offset: shadow, border: border))
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

/// Frosted window backdrop: blurred desktop, soft color blobs that slowly drift and breathe, and a faint dot grid.
struct GlassBackdrop: View {
    @State private var drifting = false

    private struct Blob {
        let color: Color
        let size: CGFloat
        let blur: CGFloat
        let origin: CGSize
        let drift: CGSize
        let opacity: Double
        let seconds: Double
    }

    private static let blobs = [
        Blob(color: Brutal.pink, size: 380, blur: 90, origin: CGSize(width: -280, height: -200), drift: CGSize(width: 70, height: 50), opacity: 0.55, seconds: 19),
        Blob(color: Brutal.sky, size: 420, blur: 100, origin: CGSize(width: 300, height: 220), drift: CGSize(width: -60, height: -70), opacity: 0.55, seconds: 23),
        Blob(color: Brutal.yellow, size: 300, blur: 90, origin: CGSize(width: 220, height: -230), drift: CGSize(width: -80, height: 60), opacity: 0.5, seconds: 17),
        Blob(color: Brutal.mint, size: 260, blur: 90, origin: CGSize(width: -220, height: 260), drift: CGSize(width: 60, height: -60), opacity: 0.45, seconds: 21),
    ]

    var body: some View {
        ZStack {
            VisualEffectBackground()
            Color.white.opacity(0.35)
            ForEach(Self.blobs.indices, id: \.self) { index in
                let blob = Self.blobs[index]
                Circle().fill(blob.color).frame(width: blob.size).blur(radius: blob.blur)
                    .offset(x: blob.origin.width + (drifting ? blob.drift.width : 0), y: blob.origin.height + (drifting ? blob.drift.height : 0))
                    .opacity(blob.opacity * (drifting ? 0.8 : 1))
                    .animation(.easeInOut(duration: blob.seconds).repeatForever(autoreverses: true), value: drifting)
            }
            Canvas { ctx, size in
                let step: CGFloat = 18
                for x in stride(from: step / 2, to: size.width, by: step) {
                    for y in stride(from: step / 2, to: size.height, by: step) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(Brutal.ink.opacity(0.10)))
                    }
                }
            }
        }
        .onAppear {
            if !QuickAccessMotion.reduced {
                drifting = true
            }
        }
    }
}

// MARK: Controls

struct BrutalButtonStyle: ButtonStyle {
    var color: Color = .white
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .bold))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .brutalSurface(color, radius: 8, shadow: pressed ? 0 : 3)
            .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
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
                RoundedRectangle(cornerRadius: 7, style: .circular)
                    .fill(configuration.isOn ? color : Color.white.opacity(0.7))
                    .frame(width: 48, height: 28)
                RoundedRectangle(cornerRadius: 4, style: .circular)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .circular).strokeBorder(Brutal.ink, lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 6)
            }
            .overlay(RoundedRectangle(cornerRadius: 7, style: .circular).strokeBorder(Brutal.ink, lineWidth: Brutal.border))
            .background(HardShadow(shape: RoundedRectangle(cornerRadius: 7, style: .circular), offset: 2, border: Brutal.border))
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .circular))
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
