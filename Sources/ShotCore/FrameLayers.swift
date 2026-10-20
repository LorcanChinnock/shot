import Foundation

enum AnnotationFrame {
    /// An annotation to draw, with the turn and fade to give it.
    struct Item: Equatable {
        var annotation: Annotation
        var rotation: Double = 0
        var opacity: Double = 1

        var isPlain: Bool { abs(rotation) < 1e-6 && opacity >= 0.999 }
    }

    /// Kinds that depend on what's under them: they blend with it, blur it, or dim all but a part of it.
    static func needsPicture(_ annotation: Annotation) -> Bool {
        switch annotation.kind {
        case .highlight, .marker, .spotlight, .pixelate, .blur: true
        case .arrow, .line, .shape, .text, .counter, .note, .freehand, .image: false
        }
    }
}

/// What a frame of a project draws at one time, bottom to top: each picture with its clip as it is then, and between them
/// the annotations showing, with those being edited swapped for what's drawn live in their place. The compositor draws
/// the layers; this decides them, so it's the same whatever draws.
enum FrameLayers {
    /// What a stretch of the timeline shows, bottom to top. `Picture` is a source frame, whatever the compositor reads.
    enum Source<Picture> {
        case picture(Picture, Clip)
        case annotation(AnnotationClip)
    }

    enum Layer<Picture> {
        /// A source frame and its clip, moved by its keyframes to where it is at the time, with the style it's drawn in.
        case picture(Picture, Clip)
        /// Annotations drawn together, bottom to top, each as it is at the time.
        case annotations([AnnotationFrame.Item])
    }

    /// The layers of `stack` at timeline `time`. An annotation clip in `hidden` is being edited: it draws its replacement
    /// in `drawn` in its place, while that's showing. The rest of `drawn`, new ones, go on top. A picture in `clipStyles`
    /// is drawn with that style in place of its own. `shaper` measures text an annotation's keyframes scale.
    static func layers<Picture>(
        of stack: [Source<Picture>], at time: Double, hidden: Set<UUID>, drawn: [AnnotationClip], clipStyles: [UUID: ObjectStyle], shaper: any TextShaper
    ) -> [Layer<Picture>] {
        let replacements = Dictionary(drawn.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var stacked: Set<UUID> = []
        var layers: [Layer<Picture>] = []
        var run: [AnnotationFrame.Item] = []
        func item(_ clip: AnnotationClip) -> AnnotationFrame.Item {
            let state = clip.rendered(atTimeline: time, shaper: shaper)
            return AnnotationFrame.Item(annotation: state.annotation, rotation: state.rotation, opacity: state.opacity)
        }
        func flush() {
            if !run.isEmpty {
                layers.append(.annotations(run))
                run = []
            }
        }
        for source in stack {
            switch source {
            case let .annotation(clip):
                // One being edited draws where it is in the stack.
                guard hidden.contains(clip.id) else {
                    run.append(item(clip))
                    continue
                }
                if let replacement = replacements[clip.id], replacement.start <= time, time < replacement.end {
                    stacked.insert(clip.id)
                    run.append(item(replacement))
                }
            case let .picture(picture, clip):
                flush()
                var placed = clip
                placed.transform = clip.transform(atTimeline: time)
                if let style = clipStyles[clip.id] {
                    placed.style = style
                }
                layers.append(.picture(picture, placed))
            }
        }
        run += drawn.filter { !stacked.contains($0.id) && $0.start <= time && time < $0.end }.map(item)
        flush()
        return layers
    }
}
