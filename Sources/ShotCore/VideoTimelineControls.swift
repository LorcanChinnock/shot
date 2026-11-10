import Foundation

/// The video editor's well, the area under the title bar the video sits in, from Edit › Video editor and export.
public enum VideoWell {
    /// Room either side of the video for the drawing tools' column, which floats 16 pt in from the well's left edge and is
    /// 40 pt wide, so it sits beside the video rather than over it.
    public static let sideInset: CGFloat = 64
    /// Room above and below the video.
    public static let verticalInset: CGFloat = 20

    /// Where the video sits in a well of `size`: `frame`'s shape, as large as fits inside the insets, centred.
    public static func videoRect(showing frame: CGSize, in size: CGSize) -> CGRect {
        let room = CGSize(width: max(0, size.width - sideInset * 2), height: max(0, size.height - verticalInset * 2))
        guard frame.width > 0, frame.height > 0, room.width > 0, room.height > 0 else {
            return CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        }
        let scale = min(room.width / frame.width, room.height / frame.height)
        let width = frame.width * scale
        let height = frame.height * scale
        let x = (size.width - width) / 2
        let y = (size.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension LaneLayout {
    /// What a lane's label in the timeline's left column says.
    public enum Name: Equatable, Sendable {
        /// An annotation lane with something other than text on it, or nothing yet.
        case draw
        /// An annotation lane holding only text.
        case text
        /// The recording, or a video added on a lane of its own.
        case video
        /// The recording's sound, or a sound added from another file.
        case sound
    }

    /// The width of the column of lane names left of the lanes.
    public static let labelWidth: CGFloat = 70
}

extension Project {
    public func laneName(ofTrack index: Int) -> LaneLayout.Name {
        let track = tracks[index]
        switch track.kind {
        case .video: return .video
        case .audio: return .sound
        case .overlay:
            let allText = !track.annotations.isEmpty && track.annotations.allSatisfy {
                if case .text = $0.annotation.kind { true } else { false }
            }
            return allText ? .text : .draw
        }
    }

    /// A cut on the main track: where the timeline jumps over it, and how many seconds of the recording it leaves out.
    public struct CutMark: Equatable, Sendable {
        public var time: Double
        public var length: Double
    }

    /// The main track's cuts, as `mainCuts` finds them, with their lengths for the timeline's cut badges.
    public var mainCutMarks: [CutMark] {
        zip(main.clips, main.clips.dropFirst()).compactMap { previous, next in
            let length = next.sourceStart - previous.sourceEnd
            return next.source == previous.source && abs(length) > Self.shortestClip ? CutMark(time: next.start, length: length) : nil
        }
    }
}

extension TimelineZoom {
    /// Where `zoom` sits on the zoom slider, 0 for the whole project and 1 for the closest, evenly per step.
    public static func sliderPosition(for zoom: Double) -> Double {
        let clamped = min(max(zoom, range.lowerBound), range.upperBound)
        return log(clamped / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }

    /// The zoom at slider `position`, the inverse of `sliderPosition(for:)`.
    public static func zoom(atSliderPosition position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        return range.lowerBound * pow(range.upperBound / range.lowerBound, clamped)
    }
}
