import ShotCore
import SwiftUI

/// The selected clip's position, scale, rotation, opacity and volume, each with a diamond that keys it at the playhead,
/// and the one-click animations. Changing a keyed property at another time adds a keyframe there.
struct ClipInspector: View {
    /// Two rows of controls and the gap between them.
    static let height: CGFloat = 2 * 32 + 8

    let model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let id = model.selectedClipID, let values = model.selectedValues, let animation = model.selectedAnimation {
                let isSound = model.project.clip(id).map { clip in model.project.tracks.contains { $0.kind == .audio && $0.clips.contains { $0.id == clip.id } } } ?? false
                let isNote = model.project.annotationClip(id) != nil
                properties(values, animation, isSound: isSound)
                HStack(spacing: 8) {
                    if !isSound {
                        ForEach(AnimationPreset.allCases, id: \.self) { preset in
                            if model.project.supports(preset, forClip: id) {
                                Button(preset.title) { model.applyPreset(preset) }
                                    .buttonStyle(BrutalButtonStyle(color: Brutal.violet.opacity(0.7), compact: true))
                                    .brutalTip("\(preset.title) animation at the start of the \(isNote ? "annotation" : "clip")")
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if let time = model.selectedKeyframe, let easing = animation.easing(at: time) {
                        Text("EASING").font(.system(size: 11, weight: .black)).tracking(1.2).foregroundStyle(Brutal.ink.opacity(0.75))
                        BrutalSegmented(selection: Binding(get: { easing }, set: { model.setKeyframeEasing($0) }), options: Easing.allCases.map { ($0, $0.title) }, color: Brutal.mint)
                            .brutalTip("How the value moves from this keyframe to the next")
                    }
                    if !animation.isEmpty {
                        Button("Clear keyframes") { model.clearKeyframes() }
                            .buttonStyle(BrutalButtonStyle(compact: true))
                    }
                }
                .frame(height: 32)
            } else {
                properties(PropertyValues(), ClipAnimation(), isSound: false)
                    .disabled(true)
                    .opacity(0.5)
                Text("Select a clip to move, scale, turn or fade it, and to key it over time.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.ink.opacity(0.7))
                    .frame(height: 32)
            }
        }
        .frame(height: Self.height)
        .disabled(model.isExporting)
    }

    // MARK: Controls

    private func properties(_ values: PropertyValues, _ animation: ClipAnimation, isSound: Bool) -> some View {
        HStack(spacing: 14) {
            if isSound {
                slider("VOLUME", property: .volume, value: values.volume, range: 0...2, format: { "\(Int(($0 * 100).rounded()))%" }, animation: animation) {
                    var changed = values
                    changed.volume = $0
                    return changed
                }
            } else {
                position(values, animation)
                slider("SCALE", property: .scale, value: log2(values.scale), range: PropertyValues.scaleDoublings, format: { String(format: "%.2f×", exp2($0)) }, animation: animation) {
                    var changed = values
                    changed.scale = exp2($0)
                    return changed
                }
                slider("TURN", property: .rotation, value: values.rotation * 180 / .pi, range: -180...180, format: { "\(Int($0.rounded()))°" }, animation: animation) {
                    var changed = values
                    changed.rotation = $0 * .pi / 180
                    return changed
                }
                slider("OPACITY", property: .opacity, value: values.opacity, range: 0...1, format: { "\(Int(($0 * 100).rounded()))%" }, animation: animation) {
                    var changed = values
                    changed.opacity = $0
                    return changed
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 32)
    }

    private func position(_ values: PropertyValues, _ animation: ClipAnimation) -> some View {
        HStack(spacing: 6) {
            caption("POSITION")
            field(values.position.width, label: "Horizontal position") { var changed = values; changed.position.width = $0; return changed }
            field(values.position.height, label: "Vertical position") { var changed = values; changed.position.height = $0; return changed }
            diamond(.position, animation)
        }
    }

    private func slider(_ title: String, property: AnimatedProperty, value: Double, range: ClosedRange<Double>, format: (Double) -> String, animation: ClipAnimation, make: @escaping (Double) -> PropertyValues) -> some View {
        HStack(spacing: 6) {
            caption(title)
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { model.setValues(make($0)) }), in: range) { editing in
                if editing {
                    model.beginDrag()
                } else {
                    model.endDrag()
                }
            }
            .frame(minWidth: 48, idealWidth: 90, maxWidth: 90, minHeight: 24, maxHeight: 24)
            .tint(Brutal.sky)
            .accessibilityLabel(Text(title.capitalized))
            .accessibilityValue(Text(format(value)))
            Text(format(value)).font(Brutal.mono).foregroundStyle(Brutal.ink.opacity(0.75)).frame(width: 48, alignment: .leading)
            diamond(property, animation)
        }
    }

    private func field(_ value: Double, label: String, make: @escaping (Double) -> PropertyValues) -> some View {
        TextField("0", value: Binding(get: { value.rounded() }, set: { model.setValues(make($0)) }), format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.plain)
            .font(Brutal.mono)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 6)
            .frame(width: 56, height: 24)
            .brutalSurface(Color.white.opacity(0.7), radius: 6, shadow: 0, border: 2)
            .accessibilityLabel(Text(label))
    }

    /// Filled when there's a keyframe of the property at the playhead, a dot when it has others, and empty when it has none.
    private func diamond(_ property: AnimatedProperty, _ animation: ClipAnimation) -> some View {
        let start = model.selectedClipID.flatMap { model.project.clipStart($0) } ?? 0
        let here = animation.hasKeyframe(property, at: model.playhead - start)
        return Button { model.toggleKeyframe(property) } label: {
            Image(systemName: here ? "diamond.fill" : "diamond")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(here ? Brutal.ink : Brutal.ink.opacity(animation.hasKeyframes(property) ? 0.9 : 0.45))
                .overlay {
                    if !here, animation.hasKeyframes(property) {
                        Circle().fill(Brutal.ink).frame(width: 4, height: 4)
                    }
                }
                .frame(width: 26, height: 26)
                .background(here ? Brutal.yellow : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .circular))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalTip(here ? "Remove this keyframe" : "Keyframe \(property.rawValue) here")
        .accessibilityLabel(Text(here ? "Remove \(property.rawValue) keyframe" : "Add \(property.rawValue) keyframe"))
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .black)).tracking(1.2).foregroundStyle(Brutal.ink.opacity(0.75)).fixedSize()
    }
}
