import ShotCore
import SwiftUI

/// The preset colours and a rainbow swatch for a custom one. With `allowsNone`,
/// a first swatch clears the colour: `nil` is transparent, with nothing drawn.
struct ColorSwatches: View {
    let selected: RGBA?
    /// The custom colour picked last in this palette, which the rainbow swatch applies again.
    let lastCustom: RGBA?
    var allowsNone = false
    let customHelp: String
    let choose: (RGBA?) -> Void
    let pickCustom: (RGBA) -> Void

    var body: some View {
        if allowsNone {
            Swatch(color: nil, isSelected: selected == nil, name: "Transparent") { choose(nil) }
        }
        ForEach(RGBA.presets.indices, id: \.self) { index in
            Swatch(color: RGBA.presets[index], isSelected: selected == RGBA.presets[index], name: EditorToolbar.colorNames[index]) {
                choose(RGBA.presets[index])
            }
        }
        CustomColorButton(
            custom: selected.flatMap { RGBA.presets.contains($0) ? nil : $0 },
            lastCustom: lastCustom,
            fallback: selected ?? RGBA(1, 1, 1),
            help: customHelp,
            pick: pickCustom
        )
    }
}

/// A rainbow chip that applies the last custom colour and opens the colour editor on it in a popover,
/// so picking stays inside the app. While a custom colour is in use, it shows inside the rainbow ring.
private struct CustomColorButton: View {
    let custom: RGBA?
    let lastCustom: RGBA?
    /// What the colour editor starts on when no custom colour has been picked yet.
    let fallback: RGBA
    let help: String
    let pick: (RGBA) -> Void
    @State private var isOpen = false

    private var isSelected: Bool { isOpen || custom != nil }

    var body: some View {
        Button(action: open) {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                if let custom {
                    Circle().fill(custom.swiftUIColor).inkBorder(Circle(), width: 2).padding(4)
                }
            }
            .inkBorder(Circle(), width: 2)
            .background(Circle().fill(Brutal.ink).offset(x: isSelected ? 2 : 0, y: isSelected ? 2 : 0))
            .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
            .frame(width: 26, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalTip(help)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(custom != nil ? .isSelected : [])
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ColorEditor(initial: lastCustom ?? fallback, pick: pick)
        }
    }

    private func open() {
        guard !isOpen else {
            isOpen = false
            return
        }
        if let lastCustom, lastCustom != custom {
            pick(lastCustom)
        }
        isOpen = true
    }
}

private struct ColorEditor: View {
    let pick: (RGBA) -> Void
    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var opacity: Double

    init(initial: RGBA, pick: @escaping (RGBA) -> Void) {
        self.pick = pick
        let c = NSColor(srgbRed: initial.r, green: initial.g, blue: initial.b, alpha: initial.a)
        _hue = State(initialValue: Double(c.hueComponent))
        _saturation = State(initialValue: Double(c.saturationComponent))
        _brightness = State(initialValue: Double(c.brightnessComponent))
        _opacity = State(initialValue: Double(initial.a))
    }

    private var color: Color { Color(hue: hue, saturation: saturation, brightness: brightness, opacity: opacity) }

    var body: some View {
        VStack(spacing: 12) {
            SaturationBrightnessField(hue: hue, saturation: $saturation, brightness: $brightness)
                .frame(width: 200, height: 140)
            BrutalSlider(
                value: $hue,
                track: LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
            )
            BrutalSlider(
                value: $opacity,
                track: LinearGradient(colors: [color.opacity(0), color.opacity(1)], startPoint: .leading, endPoint: .trailing),
                checkerboard: true
            )
            Circle().fill(color).frame(width: 22, height: 22)
                .inkBorder(Circle(), width: 2)
        }
        .padding(16)
        .onChange(of: hue) { commit() }
        .onChange(of: saturation) { commit() }
        .onChange(of: brightness) { commit() }
        .onChange(of: opacity) { commit() }
    }

    private func commit() {
        pick(RGBA(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: opacity)))
    }
}

private struct SaturationBrightnessField: View {
    let hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(hue: hue, saturation: 1, brightness: 1)
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .padding(1)
                    .inkBorder(Circle(), width: 1)
                    .position(x: saturation * size.width, y: (1 - brightness) * size.height)
            }
            .inkBorder(RoundedRectangle(cornerRadius: 6, style: .circular), width: 2)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                saturation = min(max(drag.location.x / size.width, 0), 1)
                brightness = 1 - min(max(drag.location.y / size.height, 0), 1)
            })
        }
    }
}

/// A capsule track with a round knob. `onEditingChanged` reports a drag starting and ending, so a caller
/// can make each drag one undo step.
struct BrutalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let track: LinearGradient
    var checkerboard = false
    var width: CGFloat = 200
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var isDragging = false

    private var fraction: Double { (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound) }

    var body: some View {
        ZStack(alignment: .leading) {
            if checkerboard {
                Canvas { ctx, size in
                    let cell: CGFloat = 6
                    for x in 0...Int(size.width / cell) {
                        for y in 0...Int(size.height / cell) where (x + y) % 2 == 0 {
                            ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(.gray.opacity(0.4)))
                        }
                    }
                }
                .background(Color.white)
                .clipShape(Capsule().inset(by: 1))
            }
            Capsule().fill(track)
                .inkBorder(Capsule(), width: 2)
            Circle().fill(.white)
                .inkBorder(Circle(), width: 2)
                .frame(width: 16, height: 16)
                .offset(x: fraction * (width - 16))
        }
        .frame(width: width, height: 16)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if !isDragging {
                    isDragging = true
                    onEditingChanged(true)
                }
                let dragged = min(max((drag.location.x - 8) / (width - 16), 0), 1)
                value = range.lowerBound + dragged * (range.upperBound - range.lowerBound)
            }
            .onEnded { _ in
                isDragging = false
                onEditingChanged(false)
            })
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 10
            value = min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
        }
    }
}

private struct Swatch: View {
    let color: RGBA?
    let isSelected: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color?.swiftUIColor ?? .white)
                if color == nil {
                    Rectangle().fill(Brutal.red).frame(width: 2, height: 22).rotationEffect(.degrees(45))
                }
            }
            .inkBorder(Circle(), width: 2)
            .background(Circle().fill(Brutal.ink).offset(x: isSelected ? 2 : 0, y: isSelected ? 2 : 0))
            .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
            .frame(width: 26, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalTip(name)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

struct ToolGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(Brutal.groupInset)
        .brutalSurface(Color.white.opacity(0.5), glass: true, radius: 10, shadow: 3)
    }
}

struct Tile<Label: View>: View {
    let selected: Bool
    let color: Color
    let help: String
    /// What the tile does, shown under `help` in its tip.
    var detail: String?
    /// A disabled tile is dimmed but still shows its tip.
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(Brutal.ink)
                .frame(width: 30, height: 30)
                .background {
                    if selected {
                        PartyColor(color) { Color.clear.brutalSurface($0, radius: 7, shadow: 2) }
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 7, style: .circular).fill(Brutal.ink.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
        .brutalTip(help, detail: detail)
    }
}
