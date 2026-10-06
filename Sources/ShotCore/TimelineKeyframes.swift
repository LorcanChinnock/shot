import CoreGraphics
import Foundation

/// One-click animations that fill in keyframes.
public enum AnimationPreset: String, CaseIterable, Sendable {
    case fadeIn, fadeOut, pop, slideIn, drawOn

    public var title: String {
        switch self {
        case .fadeIn: "Fade in"
        case .fadeOut: "Fade out"
        case .pop: "Pop"
        case .slideIn: "Slide in"
        case .drawOn: "Draw on"
        }
    }

    /// Whether it needs something that can be drawn a bit at a time: an arrow, line or pen stroke.
    public var needsStroke: Bool { self == .drawOn }
}

extension ClipAnimation {
    /// How long the in and out presets take, at most.
    static let presetDuration = 0.5

    /// This animation with `preset` added, for a clip `length` seconds long whose plain values are `base`,
    /// over a canvas of `canvas`. Presets add to each other and to keyframes made by hand.
    public func applying(_ preset: AnimationPreset, length: Double, base: PropertyValues, canvas: CGSize) -> ClipAnimation {
        var result = self
        let fade = min(Self.presetDuration, length / 2)
        func set(_ property: AnimatedProperty, _ time: Double, _ values: PropertyValues, easing: Easing = .linear) {
            result.set(property, at: time, to: values)
            result = result.settingEasing(easing, at: time, property: property)
        }
        func keep(_ property: AnimatedProperty, from values: PropertyValues, at time: Double) -> PropertyValues {
            // The value already there when there are keyframes, so a preset doesn't undo what was set by hand.
            hasKeyframes(property) ? self.values(at: time, base: values) : values
        }
        switch preset {
        case .fadeIn:
            var hidden = base
            hidden.opacity = 0
            set(.opacity, 0, hidden, easing: .easeOut)
            set(.opacity, fade, keep(.opacity, from: base, at: fade))
        case .fadeOut:
            var hidden = base
            hidden.opacity = 0
            set(.opacity, max(0, length - fade), keep(.opacity, from: base, at: length - fade), easing: .easeIn)
            set(.opacity, length, hidden)
        case .pop:
            var small = base
            small.scale = base.scale * 0.2
            var hidden = base
            hidden.opacity = 0
            set(.scale, 0, small, easing: .spring)
            set(.scale, min(0.45, length), base)
            set(.opacity, 0, hidden, easing: .easeOut)
            set(.opacity, min(0.15, length), base)
        case .slideIn:
            var away = base
            away.position = CGSize(width: base.position.width - canvas.width * 0.35, height: base.position.height)
            var hidden = base
            hidden.opacity = 0
            set(.position, 0, away, easing: .easeOut)
            set(.position, min(0.5, length), base)
            set(.opacity, 0, hidden, easing: .easeOut)
            set(.opacity, min(0.3, length), base)
        case .drawOn:
            var none = base
            none.reveal = 0
            var all = base
            all.reveal = 1
            set(.reveal, 0, none, easing: .easeInOut)
            set(.reveal, min(max(length * 0.6, TrimRange.minimumLength), length), all)
        }
        return result
    }

    func settingEasing(_ easing: Easing, at time: Double, property: AnimatedProperty) -> ClipAnimation {
        var only = ClipAnimation()
        only = only.replacing(property, with: self)
        return replacing(property, with: only.settingEasing(easing, at: time))
    }
}

extension Project {
    /// Sets the properties of a clip at timeline `time` to `values`. A property that has keyframes gets one at `time`
    /// holding its new value; any other just changes. Properties `values` leaves as they are, stay as they are.
    public func setting(values wanted: PropertyValues, ofClip id: UUID, at time: Double) -> Project? {
        var values = wanted
        values.opacity = min(max(values.opacity, 0), 1)
        values.scale = max(values.scale, 0.01)
        values.volume = min(max(values.volume, 0), 2)
        values.reveal = min(max(values.reveal, 0), 1)
        if let clip = clip(id) {
            let current = clip.values(atTimeline: time)
            var changed = clip
            let relative = max(0, time - clip.start)
            for property in AnimatedProperty.allCases where Self.differs(property, current, values) {
                if changed.animation.hasKeyframes(property) {
                    changed.animation.set(property, at: relative, to: values)
                } else {
                    switch property {
                    case .position: changed.transform.offset = values.position
                    case .scale: changed.transform.scale = values.scale
                    case .rotation: changed.transform.rotation = values.rotation
                    case .opacity: changed.transform.opacity = values.opacity
                    case .volume: changed.volume = min(max(values.volume, 0), 2)
                    case .reveal: break
                    }
                }
            }
            return replacing(clip: changed)
        }
        guard let note = annotationClip(id) else {
            return nil
        }
        let current = note.values(atTimeline: time)
        var changed = note
        let relative = max(0, time - note.start)
        for property in AnimatedProperty.allCases where Self.differs(property, current, values) {
            if changed.animation.hasKeyframes(property) {
                changed.animation.set(property, at: relative, to: values)
            } else {
                switch property {
                case .position: changed.transform.offset = values.position
                case .scale: changed.transform.scale = values.scale
                case .rotation: changed.transform.rotation = values.rotation
                case .opacity: changed.transform.opacity = values.opacity
                case .reveal: changed.reveal = values.reveal
                case .volume: break
                }
            }
        }
        return replacing(annotationClip: changed)
    }

    /// The properties of a clip at timeline `time`, whichever kind of clip it is.
    public func values(ofClip id: UUID, at time: Double) -> PropertyValues? {
        clip(id)?.values(atTimeline: time) ?? annotationClip(id)?.values(atTimeline: time)
    }

    /// The animation of a clip, whichever kind of clip it is.
    public func animation(ofClip id: UUID) -> ClipAnimation? {
        clip(id)?.animation ?? annotationClip(id)?.animation
    }

    public func clipStart(_ id: UUID) -> Double? {
        clip(id)?.start ?? annotationClip(id)?.start
    }

    /// Adds a keyframe of `property` at timeline `time` holding what it is there now, or removes the one that's there.
    public func togglingKeyframe(_ property: AnimatedProperty, ofClip id: UUID, at time: Double) -> Project? {
        guard let start = clipStart(id), let current = values(ofClip: id, at: time), let animation = animation(ofClip: id) else {
            return nil
        }
        return replacing(animation: animation.togglingKeyframe(property, at: max(0, time - start), current: current), ofClip: id)
    }

    /// Takes away the keyframes at `time`, in seconds from the start of the clip.
    public func removingKeyframes(ofClip id: UUID, at time: Double) -> Project? {
        animation(ofClip: id).flatMap { replacing(animation: $0.removingKeyframes(at: time), ofClip: id) }
    }

    public func settingEasing(_ easing: Easing, ofClip id: UUID, at time: Double) -> Project? {
        animation(ofClip: id).flatMap { replacing(animation: $0.settingEasing(easing, at: time), ofClip: id) }
    }

    /// Moves the keyframes at `time` to `new`, both in seconds from the start of the clip and within it.
    public func movingKeyframes(ofClip id: UUID, from time: Double, to new: Double) -> Project? {
        guard let animation = animation(ofClip: id) else {
            return nil
        }
        let length = clip(id)?.length ?? annotationClip(id)?.duration ?? 0
        return replacing(animation: animation.movingKeyframes(from: time, to: min(max(new, 0), length)), ofClip: id)
    }

    public func applying(_ preset: AnimationPreset, toClip id: UUID) -> Project? {
        guard let animation = animation(ofClip: id) else {
            return nil
        }
        let length = clip(id)?.length ?? annotationClip(id)?.duration ?? 0
        let base = clip(id)?.propertyValues ?? annotationClip(id)?.propertyValues ?? PropertyValues()
        return replacing(animation: animation.applying(preset, length: length, base: base, canvas: canvasSize), ofClip: id)
    }

    /// Whether `preset` makes sense for the clip: draw-on needs an arrow, line or pen stroke.
    public func supports(_ preset: AnimationPreset, forClip id: UUID) -> Bool {
        if clip(id) != nil {
            return !preset.needsStroke
        }
        guard let note = annotationClip(id) else {
            return false
        }
        return !preset.needsStroke || note.annotation.canReveal
    }

    // MARK: Private

    private static func differs(_ property: AnimatedProperty, _ a: PropertyValues, _ b: PropertyValues) -> Bool {
        switch property {
        case .position: abs(a.position.width - b.position.width) > 1e-9 || abs(a.position.height - b.position.height) > 1e-9
        case .scale: abs(a.scale - b.scale) > 1e-9
        case .rotation: abs(a.rotation - b.rotation) > 1e-9
        case .opacity: abs(a.opacity - b.opacity) > 1e-9
        case .volume: abs(a.volume - b.volume) > 1e-9
        case .reveal: abs(a.reveal - b.reveal) > 1e-9
        }
    }

    private func replacing(clip changed: Clip) -> Project {
        var result = self
        for track in result.tracks.indices {
            for index in result.tracks[track].clips.indices where result.tracks[track].clips[index].id == changed.id {
                result.tracks[track].clips[index] = changed
            }
        }
        return result
    }

    private func replacing(annotationClip changed: AnnotationClip) -> Project {
        var result = self
        for track in result.tracks.indices {
            for index in result.tracks[track].annotations.indices where result.tracks[track].annotations[index].id == changed.id {
                result.tracks[track].annotations[index] = changed
            }
        }
        return result
    }

    private func replacing(animation: ClipAnimation, ofClip id: UUID) -> Project? {
        if var changed = clip(id) {
            changed.animation = animation
            return replacing(clip: changed)
        }
        if var changed = annotationClip(id) {
            changed.animation = animation
            return replacing(annotationClip: changed)
        }
        return nil
    }
}
