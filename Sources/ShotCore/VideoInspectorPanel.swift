import Foundation

/// The side panel the video editor shows beside the video, from Edit › Video editor and export. The Inspector and Export
/// take turns, so the video keeps most of the window's width.
public enum VideoSidePanel: String, Equatable, Sendable {
    case inspector, export

    /// The panel showing after `panel`'s button is clicked: it opens and the other closes, or it closes when it's the one open.
    public static func toggling(_ panel: VideoSidePanel, from current: VideoSidePanel?) -> VideoSidePanel? {
        current == panel ? nil : panel
    }
}

/// What the video editor's Inspector panel shows, and how its sliders read and set the selected clip's properties.
public enum VideoInspectorPanel {
    /// What's selected on the timeline.
    public enum Selection: Equatable, Sendable {
        /// A recording, video or picture clip.
        case clip
        case annotation
        /// A clip on a sound lane, which has only a volume.
        case sound
    }

    public enum Section: Hashable, Sendable {
        /// With nothing selected: the video's size, Crop and Reset.
        case frame
        /// A control for each property the selection can key.
        case properties
        /// The selected keyframe's easing, and Clear Keyframes.
        case keyframes
        /// The one-click animations, such as Fade In.
        case animations
        /// The corners, shadow and border.
        case style
        /// The clip's own crop.
        case crop
    }

    /// The panel's sections, top to bottom. `hasKeyframes` says whether the selection has any keyframe, `animates` whether
    /// any one-click animation suits it, and `canStyle` whether it takes a shadow or border.
    public static func sections(selection: Selection?, hasKeyframes: Bool, animates: Bool, canStyle: Bool) -> [Section] {
        guard let selection else {
            return [.frame]
        }
        var sections: [Section] = [.properties]
        if hasKeyframes {
            sections.append(.keyframes)
        }
        guard selection != .sound else {
            return sections
        }
        if animates {
            sections.append(.animations)
        }
        if canStyle {
            sections.append(.style)
        }
        if selection == .clip {
            sections.append(.crop)
        }
        return sections
    }

    /// The range a property's slider runs over, in the slider's own units: doublings for the scale, so 1× sits in the
    /// middle and each doubling gets equal travel, and degrees for the turn. `nil` for the position, which has two fields.
    public static func sliderRange(_ property: AnimatedProperty) -> ClosedRange<Double>? {
        switch property {
        case .position: nil
        case .scale: PropertyValues.scaleDoublings
        case .rotation: -180...180
        case .opacity, .reveal: 0...1
        case .volume: 0...2
        }
    }

    /// Where `values` puts the property's slider, kept inside its range.
    public static func sliderValue(_ property: AnimatedProperty, of values: PropertyValues) -> Double {
        guard let range = sliderRange(property) else {
            return 0
        }
        let raw: Double = switch property {
        case .position: 0
        case .scale: log2(max(values.scale, .leastNonzeroMagnitude))
        case .rotation: values.rotation * 180 / .pi
        case .opacity: values.opacity
        case .volume: values.volume
        case .reveal: values.reveal
        }
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    /// Where a new clip puts the property's slider, which the slider marks as its default.
    public static func sliderDefault(_ property: AnimatedProperty) -> Double {
        sliderValue(property, of: PropertyValues())
    }

    /// `values` with the property set from its slider at `slider`.
    public static func setting(_ property: AnimatedProperty, slider: Double, in values: PropertyValues) -> PropertyValues {
        var changed = values
        switch property {
        case .position: break
        case .scale: changed.scale = exp2(slider)
        case .rotation: changed.rotation = slider * .pi / 180
        case .opacity: changed.opacity = slider
        case .volume: changed.volume = slider
        case .reveal: changed.reveal = slider
        }
        return changed
    }

    /// The value shown beside the property's name: "1.50×", "45°" or "80%". A position reads "120, −40".
    public static func label(_ property: AnimatedProperty, of values: PropertyValues) -> String {
        switch property {
        case .position: "\(whole(values.position.width)), \(whole(values.position.height))"
        case .scale: String(format: "%.2f×", values.scale)
        case .rotation: "\(whole(values.rotation * 180 / .pi))°"
        case .opacity: percent(values.opacity)
        case .volume: percent(values.volume)
        case .reveal: percent(values.reveal)
        }
    }

    private static func percent(_ value: Double) -> String {
        "\(whole(value * 100))%"
    }

    /// Rounded to a whole number, with a true minus sign and never "-0".
    private static func whole(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded < 0 ? "−\(-rounded)" : "\(rounded)"
    }
}
