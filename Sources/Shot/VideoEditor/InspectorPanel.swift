import ShotCore
import SwiftUI

/// The Inspector beside the video, in the side panel the Export panel uses, from Edit › Video editor and export. With a
/// clip or annotation selected it shows each property the selection can key, as `Project.keyableProperties` lists them,
/// with a diamond that keys it at the playhead; then the selected keyframe's easing, the one-click animations, the
/// corners, shadow and border, and a clip's crop. With nothing selected it shows the video's frame. Changing a keyed
/// property at another time adds a keyframe there. `VideoInspectorPanel` in ShotCore decides the sections.
struct InspectorPanel: View {
    let model: VideoEditorModel

    static let width: CGFloat = 272
    /// The panel's width less its 16 pt sides, which the sliders fill.
    private static let inner: CGFloat = width - 32

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .disabled(model.isExporting)
        }
        .sidePanel(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Inspector"))
    }

    /// "Inspector" in 13 pt bold, and Reset as an accent-text link: it puts the selection back, or takes off the frame's
    /// crop with nothing selected, and greys out when there's nothing to put back.
    private var header: some View {
        HStack {
            Text("Inspector")
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Reset") { reset() }
                .buttonStyle(PanelLinkStyle())
                .disabled(resetIsDisabled)
                .themeTip("Reset", detail: resetDetail)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private func reset() {
        if model.selectedClipID == nil {
            model.removeFrameCrop()
        } else {
            model.resetSelectedClip()
        }
    }

    private var resetIsDisabled: Bool {
        guard !model.isExporting else {
            return true
        }
        return model.selectedClipID == nil ? model.project.frameCrop == nil : model.selectedClipIsAtDefaults
    }

    private var resetDetail: LocalizedStringResource {
        if model.selectedClipID == nil {
            "Shows the whole frame again."
        } else if selection == .sound {
            "Puts the volume back and clears its keyframes."
        } else {
            "Puts the position, scale, turn and opacity back and clears the keyframes. The crop and style stay."
        }
    }

    // MARK: Sections

    private var selection: VideoInspectorPanel.Selection? {
        guard let id = model.selectedClipID else {
            return nil
        }
        if model.project.annotationClip(id) != nil {
            return .annotation
        }
        return model.project.keyableProperties(ofClip: id) == [.volume] ? .sound : .clip
    }

    @ViewBuilder
    private var content: some View {
        if let id = model.selectedClipID, let values = model.selectedValues, let animation = model.selectedAnimation, let selection {
            let sections = VideoInspectorPanel.sections(
                selection: selection, hasKeyframes: !animation.isEmpty,
                animates: AnimationPreset.allCases.contains { model.project.supports($0, forClip: id) },
                canStyle: model.targetStyleKind != nil
            )
            groupTitle(Self.title(of: selection))
            ForEach(sections, id: \.self) { section in
                switch section {
                case .properties:
                    ForEach(model.project.keyableProperties(ofClip: id), id: \.self) { property in
                        control(property, values, animation)
                    }
                case .keyframes: keyframes(animation)
                case .animations: animations(id, isNote: selection == .annotation)
                case .style: style
                case .crop: crop(id)
                case .frame: EmptyView()
                }
            }
        } else {
            frame
        }
    }

    private static func title(of selection: VideoInspectorPanel.Selection) -> LocalizedStringResource {
        switch selection {
        case .clip: "Selected clip"
        case .annotation: "Selected annotation"
        case .sound: "Selected sound"
        }
    }

    private func groupTitle(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.scaled(12, weight: .bold))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The video's size and Crop, with nothing selected.
    private var frame: some View {
        let output = model.project.outputRect
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Frame").panelHeading()
                HStack(spacing: 10) {
                    Text(verbatim: "\(Int(output.width)) × \(Int(output.height))")
                        .font(.scaled(12, weight: .bold, design: .monospaced, tabular: true))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel(Text("Frame size, \(Int(output.width)) by \(Int(output.height)) pixels"))
                    Spacer(minLength: 8)
                    Button("Crop") { model.beginFrameCrop() }
                        .buttonStyle(ThemeButtonStyle())
                        .themeTip("Crop", key: "C", detail: "Crops the video's frame.")
                }
            }
            note("Select a clip or annotation to move, scale, turn or fade it, and to key it over time.")
        }
    }

    // MARK: Properties

    private static func name(_ property: AnimatedProperty) -> LocalizedStringResource {
        switch property {
        case .position: "Position"
        case .scale: "Scale"
        case .rotation: "Turn"
        case .opacity: "Opacity"
        case .volume: "Volume"
        case .reveal: "Drawn"
        }
    }

    @ViewBuilder
    private func control(_ property: AnimatedProperty, _ values: PropertyValues, _ animation: ClipAnimation) -> some View {
        if let range = VideoInspectorPanel.sliderRange(property) {
            PanelSliderRow(
                name: Self.name(property), value: VideoInspectorPanel.sliderValue(property, of: values), range: range,
                shown: VideoInspectorPanel.label(property, of: values), width: Self.inner,
                set: { slider in
                    // Read afresh, since a drag changes the values under the closure the slider holds.
                    if let current = model.selectedValues {
                        model.setValues(VideoInspectorPanel.setting(property, slider: slider, in: current))
                    }
                },
                editing: model.setDraggingStyle
            ) {
                diamond(property, animation)
            }
        } else {
            position(values, animation)
        }
    }

    /// "Position" over two fields, X and Y, sharing the panel's width.
    private func position(_ values: PropertyValues, _ animation: ClipAnimation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(Self.name(.position))
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                diamond(.position, animation)
            }
            HStack(spacing: 8) {
                field("X", value: values.position.width, label: "Horizontal position") { var changed = $0; changed.position.width = $1; return changed }
                field("Y", value: values.position.height, label: "Vertical position") { var changed = $0; changed.position.height = $1; return changed }
            }
        }
    }

    private func field(_ axis: String, value: Double, label: LocalizedStringResource, make: @escaping (PropertyValues, Double) -> PropertyValues) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: axis)
                .font(.scaled(11, weight: .semibold, design: .monospaced))
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .accessibilityHidden(true)
            NumberField(value: Binding(get: { value.rounded() }, set: { typed in
                if let current = model.selectedValues {
                    model.setValues(make(current, typed))
                }
            }), label: label)
        }
        .frame(maxWidth: .infinity)
    }

    /// Accent with an ink diamond when there's a keyframe of the property at the playhead, an outline with a dot when it
    /// has others, and a faint outline when it has none.
    private func diamond(_ property: AnimatedProperty, _ animation: ClipAnimation) -> some View {
        let name = String(localized: Self.name(property))
        let start = model.selectedClipID.flatMap { model.project.clipStart($0) } ?? 0
        let here = animation.hasKeyframe(property, at: model.playhead - start)
        let others = animation.hasKeyframes(property)
        let chip = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
        return Button { model.toggleKeyframe(property) } label: {
            Image(systemName: here ? "diamond.fill" : "diamond")
                .font(.scaled(11, weight: .bold))
                .foregroundStyle(here ? AnyShapeStyle(Theme.line) : AnyShapeStyle(ContrastAware(standard: Theme.ink.opacity(others ? 0.85 : 0.45), increased: Theme.ink)))
                .overlay {
                    if !here, others {
                        Circle().fill(Theme.ink).frame(width: 3, height: 3)
                    }
                }
                .frame(width: 22, height: 20)
                .background(here ? Theme.yellow : Color.clear, in: chip)
                .overlay {
                    if here {
                        Color.clear.inkBorder(chip, width: 1, color: Theme.line)
                    }
                }
                .contentShape(chip)
        }
        .buttonStyle(.plain)
        .themeTip(here ? String(localized: "Remove this keyframe") : String(localized: "Keyframe \(name) here"), key: "K", detail: String(localized: "K keys every property at once."))
        .accessibilityLabel(Text(here ? "Remove \(name) keyframe" : "Add \(name) keyframe"))
    }

    // MARK: Keyframes and animations

    /// The selected keyframe's easing, or how to pick one, and Clear Keyframes.
    private func keyframes(_ animation: ClipAnimation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyframes").panelHeading()
            if let time = model.selectedKeyframe, let easing = animation.easing(at: time) {
                HStack(spacing: 10) {
                    Text("Easing")
                        .font(.scaled(12, weight: .semibold))
                        .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    ThemePopUp(title: "Easing", entries: Easing.allCases.map { option in
                        .item(option.title, selected: option == easing) { model.setKeyframeEasing(option) }
                    }, value: easing.title)
                    .themeTip("Easing", detail: "How the value moves from this keyframe to the next.")
                }
            } else {
                note("Click a diamond on the lane to choose how it eases to the next one.")
            }
            Button("Clear Keyframes") { model.clearKeyframes() }
                .buttonStyle(ThemeButtonStyle())
                .themeTip("Clear Keyframes", detail: "Takes away every keyframe of the selection.")
        }
    }

    /// The one-click animations the selection suits, two to a row.
    private func animations(_ id: UUID, isNote: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Animations").panelHeading()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                ForEach(AnimationPreset.allCases.filter { model.project.supports($0, forClip: id) }, id: \.self) { preset in
                    Button { model.applyPreset(preset) } label: {
                        Text(verbatim: preset.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ThemeButtonStyle())
                    .themeTip(preset.title, detail: Self.presetDetail(preset, isNote: isNote))
                }
            }
        }
    }

    private static func presetDetail(_ preset: AnimationPreset, isNote: Bool) -> String {
        switch (preset.playsAtEnd, isNote) {
        case (true, true): String(localized: "Adds its keyframes at the end of the annotation.")
        case (true, false): String(localized: "Adds its keyframes at the end of the clip.")
        case (false, true): String(localized: "Adds its keyframes at the start of the annotation.")
        case (false, false): String(localized: "Adds its keyframes at the start of the clip.")
        }
    }

    // MARK: Style and crop

    /// A separator, "Style" with its own Reset, then the corners, shadow and border the image editor's Style panel has.
    @ViewBuilder
    private var style: some View {
        if let kind = model.targetStyleKind {
            let sections = StylePanelLayout.sections(
                kind: kind, windowShadow: false, borders: !kind.borders(transparent: model.targetHasTransparency).isEmpty
            ).target.filter { [.corners, .shadow, .border].contains($0) }
            Divider().overlay(Theme.separator)
            HStack {
                groupTitle("Style")
                Spacer(minLength: 8)
                Button("Reset") { model.resetTargetStyle() }
                    .buttonStyle(PanelLinkStyle())
                    .disabled(kind.isDefault(style: model.targetStyle, cornerRadius: model.targetCornerRadius))
                    .themeTip("Reset Style", detail: "Puts the shadow, border and corners back to how new ones start.")
                    .accessibilityLabel(Text("Reset Style"))
            }
            ForEach(sections, id: \.self) { section in
                StyleSection(model: model, section: section, sliderWidth: Self.inner)
            }
        }
    }

    /// Crop, and Reset Crop once the clip has one.
    private func crop(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crop").panelHeading()
            HStack(spacing: 8) {
                Button("Crop") { model.beginClipCrop(id) }
                    .buttonStyle(ThemeButtonStyle())
                    .themeTip("Crop", key: "C", detail: "Crops the clip's picture.")
                if model.selectedClip?.crop != nil {
                    Button("Reset Crop") { model.removeClipCrop() }
                        .buttonStyle(ThemeButtonStyle())
                        .themeTip("Reset Crop", detail: "Shows all of the clip's picture again.")
                }
            }
        }
    }
}

/// A whole number typed into a field, such as a clip's position.
private struct NumberField: View {
    @Binding var value: Double
    let label: LocalizedStringResource
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0", value: $value, format: .number.precision(.fractionLength(0)))
            .font(.scaled(12, design: .monospaced, tabular: true))
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .themeField(focused: focused)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(label))
    }
}
