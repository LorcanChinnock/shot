import ShotCore
import SwiftUI

/// The preset colours and a rainbow swatch for a custom one. With `allowsNone`,
/// a first swatch clears the colour: `nil` is transparent, with nothing drawn.
struct ColorSwatches: View {
    let selected: RGBA?
    /// The custom colour picked last in this palette, which the rainbow swatch applies again.
    let lastCustom: RGBA?
    var allowsNone = false
    let customHelp: LocalizedStringResource
    let choose: (RGBA?) -> Void
    let pickCustom: (RGBA) -> Void
    /// Called as the colour editor opens, so its picks are an undo step of their own rather than joining the last time's.
    let beginPicking: () -> Void
    /// Called with true as the colour editor opens and false as it closes.
    var editorShown: (Bool) -> Void = { _ in }

    var body: some View {
        if allowsNone {
            Swatch(color: nil, isSelected: selected == nil, name: String(localized: "Transparent")) { choose(nil) }
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
            help: String(localized: customHelp),
            pick: pickCustom,
            beginPicking: beginPicking,
            editorShown: editorShown
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
    let beginPicking: () -> Void
    let editorShown: (Bool) -> Void
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
            .background(Circle().fill(Brutal.line).offset(x: isSelected ? 2 : 0, y: isSelected ? 2 : 0))
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
        .onChange(of: isOpen) { editorShown(isOpen) }
    }

    private func open() {
        guard !isOpen else {
            isOpen = false
            return
        }
        beginPicking()
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
    /// The colour sampled last and the values it set, so committing those values applies it exactly, not its HSB round trip.
    @State private var sampled: (color: RGBA, values: [Double])?

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
            .accessibilityLabel(Text("Hue"))
            BrutalSlider(
                value: $opacity,
                track: LinearGradient(colors: [color.opacity(0), color.opacity(1)], startPoint: .leading, endPoint: .trailing),
                checkerboard: true
            )
            .accessibilityLabel(Text("Opacity"))
            HStack {
                Button(action: sample) {
                    Image(systemName: "eyedropper")
                }
                .buttonStyle(BrutalButtonStyle(compact: true))
                .brutalTip("Pick a colour on screen", detail: "Click anywhere, including the image. Esc cancels.")
                .accessibilityLabel(Text("Pick a colour on screen"))
                Spacer()
                Circle().fill(color).frame(width: 22, height: 22)
                    .inkBorder(Circle(), width: 2)
            }
            .frame(width: 200)
        }
        .padding(16)
        .onChange(of: hue) { commit() }
        .onChange(of: saturation) { commit() }
        .onChange(of: brightness) { commit() }
        .onChange(of: opacity) { commit() }
    }

    private var values: [Double] { [hue, saturation, brightness, opacity] }

    private func commit() {
        if let sampled, sampled.values == values {
            pick(sampled.color)
        } else {
            pick(RGBA(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: opacity)))
        }
    }

    /// Moves the editor to the colour sampled and applies it exactly, in the same undo step as the editor's other picks.
    private func sample() {
        Task {
            guard let picked = await ColorSampler.sample() else {
                return
            }
            let c = NSColor(srgbRed: picked.r, green: picked.g, blue: picked.b, alpha: picked.a)
            sampled = (picked, [Double(c.hueComponent), Double(c.saturationComponent), Double(c.brightnessComponent), Double(picked.a)])
            hue = Double(c.hueComponent)
            saturation = Double(c.saturationComponent)
            brightness = Double(c.brightnessComponent)
            opacity = Double(picked.a)
            // The values may not have changed, which commits nothing, so apply it here too.
            pick(picked)
        }
    }
}

/// Dragging sets saturation across and brightness up. Once focused, the arrow keys do too, ⇧ in bigger steps.
private struct SaturationBrightnessField: View {
    let hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(hue: hue, saturation: 1, brightness: 1)
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
            }
            .inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.chip, style: .circular), width: 2)
            // Outside the border's clip, so at an edge the marker and its focus ring draw whole, over the border.
            .overlay {
                Circle().fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: 14, height: 14)
                    .inkBorder(Circle(), width: 2, color: isFocused ? Brutal.yellow : .white)
                    .padding(1)
                    .inkBorder(Circle(), width: 1)
                    .position(x: saturation * size.width, y: (1 - brightness) * size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                saturation = min(max(drag.location.x / size.width, 0), 1)
                brightness = 1 - min(max(drag.location.y / size.height, 0), 1)
            })
        }
        .focusable(interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            let fraction = press.modifiers.contains(.shift) ? 0.1 : 0.01
            switch press.key {
            case .leftArrow, .rightArrow:
                saturation = SliderStep.value(saturation, up: press.key == .rightArrow, fraction: fraction, in: 0...1)
            default:
                brightness = SliderStep.value(brightness, up: press.key == .upArrow, fraction: fraction, in: 0...1)
            }
            return .handled
        }
        // One slider can't hold two values, so assistive tech sees a group of two sliders, one per axis.
        .accessibilityRepresentation {
            VStack {
                Slider(value: $saturation, in: 0...1, step: 0.1) { Text("Saturation") }
                    .accessibilityValue(Text("\(percent(saturation)) percent"))
                Slider(value: $brightness, in: 0...1, step: 0.1) { Text("Brightness") }
                    .accessibilityValue(Text("\(percent(brightness)) percent"))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Saturation and brightness"))
        }
    }

    private func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
}

/// A capsule track with a round knob. Once focused, the arrow keys step it by 1% of its range, ⇧ by 10%.
/// `onEditingChanged` reports a drag, or an arrow key held down, starting and ending, so a caller can make each one
/// undo step.
struct BrutalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let track: LinearGradient
    var checkerboard = false
    var width: CGFloat = 200
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var isDragging = false
    /// Whether an arrow key is down, so its repeats join one edit.
    @State private var isStepping = false
    /// The value the arrow key held down set last. Its repeats reach the handler its press began with, whose `value` may
    /// be a copy from before the press, so each repeat steps from this instead.
    @State private var steppedValue: Double?
    @FocusState private var isFocused: Bool

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
            Circle().fill(isFocused ? Brutal.yellow : Brutal.paper)
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
        .focusable(interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .all) { press in
            guard press.phase != .up else {
                endStepping()
                return .handled
            }
            if !isStepping {
                isStepping = true
                onEditingChanged(true)
            }
            let up = press.key == .rightArrow || press.key == .upArrow
            let from = press.phase == .repeat ? steppedValue ?? value : value
            let stepped = SliderStep.value(from, up: up, fraction: press.modifiers.contains(.shift) ? 0.1 : 0.01, in: range)
            steppedValue = stepped
            value = stepped
            return .handled
        }
        .onChange(of: isFocused) {
            if !isFocused {
                endStepping()
            }
        }
        // A real slider to assistive tech, stepping by 10% of the range. A caller's label after this applies to it.
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: (range.upperBound - range.lowerBound) / 10)
                .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
        }
    }

    /// Ends the edit a held arrow key started. A key let go after focus moved away never reports its release.
    private func endStepping() {
        guard isStepping else {
            return
        }
        isStepping = false
        steppedValue = nil
        onEditingChanged(false)
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
                Circle().fill(color?.swiftUIColor ?? Brutal.paper)
                if color == nil {
                    Rectangle().fill(Brutal.red).frame(width: 2, height: 22).rotationEffect(.degrees(45))
                }
            }
            .inkBorder(Circle(), width: 2)
            .background(Circle().fill(Brutal.line).offset(x: isSelected ? 2 : 0, y: isSelected ? 2 : 0))
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
        .brutalSurface(Brutal.paper.opacity(0.5), glass: true, radius: Brutal.Radius.panel, shadow: 3)
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

    init(selected: Bool, color: Color, help: LocalizedStringResource, detail: LocalizedStringResource? = nil, isEnabled: Bool = true, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.init(selected: selected, color: color, help: String(localized: help), detail: detail.map { String(localized: $0) }, isEnabled: isEnabled, action: action, label: label)
    }

    /// A tile whose help is already localized, such as a tool's title.
    @_disfavoredOverload
    init<S: StringProtocol>(selected: Bool, color: Color, help: S, detail: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.selected = selected
        self.color = color
        self.help = String(help)
        self.detail = detail
        self.isEnabled = isEnabled
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(Brutal.ink)
                .frame(width: 30, height: 30)
                .inkOnFill(selected ? color : nil)
                .background {
                    if selected {
                        Color.clear.brutalSurface(color, radius: Brutal.Radius.inset, shadow: 2)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: Brutal.Radius.inset, style: .circular).fill(Brutal.ink.opacity(0.08))
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
