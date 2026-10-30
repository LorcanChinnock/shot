import CoreGraphics
import Foundation

/// What crop mode of the video editor is adjusting: the video's frame, or one clip's picture.
public enum VideoCropTarget: Equatable, Sendable {
    case frame
    case clip(UUID)
}

extension Project {
    /// What the player shows while `target` is being adjusted: the project with that crop taken off so all of its picture shows.
    public func showing(cropping target: VideoCropTarget?) -> Project {
        switch target {
        case nil: self
        case .frame: setting(frameCrop: nil)
        case let .clip(id): setting(crop: nil, of: id) ?? self
        }
    }

    /// What the crop of `target` can reach: the canvas for the frame, or the whole picture for a clip.
    public func cropBounds(of target: VideoCropTarget?) -> CGRect? {
        switch target {
        case nil: nil
        case .frame: CGRect(origin: .zero, size: canvasSize)
        case let .clip(id): clip(id).map { CGRect(origin: .zero, size: $0.size) }
        }
    }

    /// The project with `draft`, a crop within `bounds`, applied to `target`; `nil` when the clip is gone or has no picture.
    public func applying(cropDraft draft: CGRect, bounds: CGRect, to target: VideoCropTarget) -> Project? {
        switch target {
        case .frame:
            setting(frameCrop: draft)
        case let .clip(id):
            setting(crop: ImageCrop(visible: draft, within: bounds), of: id)
        }
    }

    /// The clip, of either kind, and keyframe still selected once the project is restored to this one: the ones it still has. A keyframe
    /// this project doesn't have can't be worked on, and Delete would act on nothing.
    public func keepingSelection(clip: UUID?, keyframe: Double?) -> (clip: UUID?, keyframe: Double?) {
        let kept = clip.flatMap { self.clip($0) != nil || annotationClip($0) != nil ? $0 : nil }
        let animation = kept.flatMap(self.animation(ofClip:))
        let keptKeyframe = keyframe.flatMap { time in
            AnimatedProperty.allCases.contains { animation?.hasKeyframe($0, at: time) == true } ? time : nil
        }
        return (kept, keptKeyframe)
    }
}

/// Marking a section of the timeline to cut.
public enum TimelineSelection {
    public static func clamped(_ time: Double, to duration: Double) -> Double {
        min(max(time, 0), duration)
    }

    /// The section between `anchor` and `time`, kept within `duration`, with the time to show: `time`. No range when the two meet.
    public static func range(from anchor: Double, to time: Double, duration: Double) -> (range: Range<Double>?, shownTime: Double) {
        let ends = (clamped(anchor, to: duration), clamped(time, to: duration))
        return (ends.0 == ends.1 ? nil : min(ends.0, ends.1)..<max(ends.0, ends.1), ends.1)
    }
}
