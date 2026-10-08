import CoreGraphics
import Foundation

/// A stretch of the timeline over which the same clips are on screen.
public struct VideoSegment: Equatable, Sendable {
    public enum Layer: Equatable, Sendable {
        case clip(UUID)
        case annotation(UUID)
    }

    public var range: Range<Double>
    /// What's drawn, bottom to top: video clips and annotation clips in the order of their tracks.
    public var layers: [Layer]

    public var clips: [UUID] {
        layers.compactMap { if case let .clip(id) = $0 { id } else { nil } }
    }

    public var annotations: [UUID] {
        layers.compactMap { if case let .annotation(id) = $0 { id } else { nil } }
    }
}

extension Project {
    /// Video tracks that draw, bottom to top.
    public var videoTracks: [Track] {
        tracks.filter { $0.kind == .video && !$0.isHidden }
    }

    /// The timeline cut wherever a clip starts or ends, with what shows in each piece.
    /// Pieces with nothing in them show the canvas background.
    public func videoSegments() -> [VideoSegment] {
        let total = duration
        let shown = tracks.filter { $0.kind != .audio && !$0.isHidden }
        let edges = Set(shown.flatMap { $0.clips.flatMap { [$0.start, $0.end] } + $0.annotations.flatMap { [$0.start, $0.end] } } + [0, total]).filter { $0 >= 0 && $0 <= total }.sorted()
        var segments: [VideoSegment] = []
        for (from, to) in zip(edges, edges.dropFirst()) where to - from >= Self.shortestClip {
            let active = shown.flatMap { track in
                track.clips.filter { $0.start <= from + 1e-9 && $0.end >= to - 1e-9 }.map { VideoSegment.Layer.clip($0.id) }
                    + track.annotations.filter { $0.start <= from + 1e-9 && $0.end >= to - 1e-9 }.map { VideoSegment.Layer.annotation($0.id) }
            }
            if let last = segments.last, last.layers == active {
                segments[segments.count - 1].range = last.range.lowerBound..<to
            } else {
                segments.append(VideoSegment(range: from..<to, layers: active))
            }
        }
        return segments
    }
}

public enum LayerGeometry {
    /// Maps a clip's picture, with its origin at its top left and y down, onto a canvas the same way:
    /// scaled to fit, then scaled, rotated and moved by the clip's transform about the canvas centre.
    public static func transform(for clip: Clip, canvas: CGSize) -> CGAffineTransform {
        guard clip.size.width > 0, clip.size.height > 0 else {
            return .identity
        }
        let fit = min(canvas.width / clip.size.width, canvas.height / clip.size.height) * clip.transform.scale
        return CGAffineTransform(translationX: -clip.size.width / 2, y: -clip.size.height / 2)
            .concatenating(CGAffineTransform(scaleX: fit, y: fit))
            .concatenating(CGAffineTransform(rotationAngle: clip.transform.rotation))
            .concatenating(CGAffineTransform(translationX: canvas.width / 2 + clip.transform.offset.width, y: canvas.height / 2 + clip.transform.offset.height))
    }

    /// Where a clip's picture lands on the canvas.
    public static func frame(of clip: Clip, canvas: CGSize) -> CGRect {
        CGRect(origin: .zero, size: clip.size).applying(transform(for: clip, canvas: canvas))
    }

    /// `transform(for:canvas:)` for Core Image's y-up coordinates, applied to a source picture of `sourceHeight`
    /// whose own orientation is `orientation` (the file's preferred transform, with its origin at the top left).
    public static func imageTransform(orientation: CGAffineTransform, geometry: CGAffineTransform, sourceHeight: CGFloat, canvasHeight: CGFloat) -> CGAffineTransform {
        let flipSource = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: sourceHeight))
        let flipCanvas = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: canvasHeight))
        return flipSource.concatenating(orientation).concatenating(geometry).concatenating(flipCanvas)
    }
}
