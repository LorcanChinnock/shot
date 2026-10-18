#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

extension Project {
    /// The project showing only `rect` of its canvas, drawn `scale` times as big: a crop, a smaller copy, or both. Every
    /// picture keeps where it is and how big it looks, so it's moved and rescaled within the new canvas, with its style,
    /// and the annotations move and scale with it. `nil` when a clip or annotation is animated in position or scale, whose
    /// keyframes would need the same change, or when that leaves no canvas.
    public func reframed(to rect: CGRect, scale k: CGFloat = 1) -> Project? {
        let clips = tracks.flatMap(\.clips), notes = tracks.flatMap(\.annotations)
        guard k > 0, clips.allSatisfy({ $0.animation.position.isEmpty && $0.animation.scale.isEmpty }),
              notes.allSatisfy({ $0.animation.position.isEmpty && $0.animation.scale.isEmpty })
        else {
            return nil
        }
        let size = CGSize(width: CGFloat(Geometry.evenFloor(rect.width * k)), height: CGFloat(Geometry.evenFloor(rect.height * k)))
        guard size.width >= 2, size.height >= 2 else {
            return nil
        }
        let old = canvasSize
        // How far the old canvas centre is from the new one's, in old canvas pixels.
        let shift = CGSize(width: old.width / 2 - rect.midX, height: old.height / 2 - rect.midY)
        var result = self
        result.canvasSize = size
        // A frame crop stays on the same part of the picture, in the new canvas's pixels.
        result.frameCrop = frameCrop.flatMap { crop in
            VideoFrameCrop.normalized(CGRect(x: (crop.minX - rect.minX) * k, y: (crop.minY - rect.minY) * k, width: crop.width * k, height: crop.height * k), canvas: size)
        }
        for track in result.tracks.indices {
            for index in result.tracks[track].clips.indices {
                var clip = result.tracks[track].clips[index]
                guard clip.size.width > 0, clip.size.height > 0 else {
                    continue
                }
                let oldFit = min(old.width / clip.size.width, old.height / clip.size.height)
                let newFit = min(size.width / clip.size.width, size.height / clip.size.height)
                let scale = clip.transform.scale * Double(oldFit * k / newFit)
                // A style is in canvas pixels at the clip's scale, so it's rescaled to look the same at the new one.
                let restyle = CGFloat(clip.transform.scale / scale) * k
                clip.style = clip.style.scaled(by: restyle)
                clip.cornerRadius *= restyle
                clip.transform.offset = CGSize(width: (clip.transform.offset.width + shift.width) * k, height: (clip.transform.offset.height + shift.height) * k)
                clip.transform.scale = scale
                result.tracks[track].clips[index] = clip
            }
            for index in result.tracks[track].annotations.indices {
                var note = result.tracks[track].annotations[index]
                note.annotation = note.annotation.reframed(origin: rect.origin, scale: k)
                note.transform.offset = CGSize(width: note.transform.offset.width * k, height: note.transform.offset.height * k)
                result.tracks[track].annotations[index] = note
            }
        }
        return result
    }

    /// The project with `edit`'s changes, as the video editor makes them, on an input that plays this project's
    /// timeline: `keep` or `cut`, then `marks`, timed and placed in the input's seconds and pixels, then `appended`, one
    /// for each of `edit.append`, then `crop`. Speed, sound, format and size are the export's.
    public func applying(_ edit: VideoEdit, appended: [ImportedMedia] = []) throws(ShotCommandError) -> Project {
        let length = duration
        var result = self
        let removed = try edit.removed(from: length)
        // From the end, so each range is still where the input had it.
        for range in removed.reversed() {
            guard let cut = result.deleting(range: range) else {
                throw .data("\(edit.keep.isEmpty ? "cut" : "keep") leaves less than \(String(format: "%g", TrimRange.minimumLength)) s of the video")
            }
            result = cut
        }

        // Widths an agent leaves out look as they would drawn in the video editor.
        let lineWidth = EditorStyle.widths[1] * max(1, canvasSize.width / 960)
        for (index, timed) in edit.marks.enumerated() {
            guard timed.start < length else {
                throw .data("marks[\(index)].start is \(String(format: "%g", timed.start)) s, past the end of the \(String(format: "%.2f", length)) s video")
            }
            guard let annotation = Annotation(mark: timed.mark, lineWidth: lineWidth) else {
                throw .data("marks[\(index)] (\(timed.mark.type)) can't be drawn")
            }
            let start = VideoEdit.time(timed.start, after: removed), end = VideoEdit.time(min(timed.end, length), after: removed)
            guard end - start >= TrimRange.minimumLength else {
                throw .data("marks[\(index)] is in a part that's cut, so it would never show")
            }
            result = result.adding(annotation: annotation, at: start, duration: end - start).project
        }

        guard appended.count == edit.append.count else {
            throw .internal("expected \(edit.append.count) videos to append, got \(appended.count)")
        }
        for (index, media) in appended.enumerated() {
            guard let joined = result.appending(media) else {
                throw .data("append[\(index)]: \(media.source.lastPathComponent) has no picture, or is shorter than \(String(format: "%g", Project.shortestClip)) s")
            }
            result = joined.project
        }

        if let crop = edit.crop {
            let canvas = CGRect(origin: .zero, size: canvasSize)
            let rect = CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3]).intersection(canvas).integral
            guard !rect.isNull, rect.width >= 16, rect.height >= 16 else {
                throw .data("crop (\(CropRegion.text(crop))) keeps less than 16×16 of the \(Int(canvasSize.width))×\(Int(canvasSize.height)) video")
            }
            guard let cropped = result.reframed(to: rect) else {
                throw .data("crop: the video has clips or marks that move or scale over time; crop it before animating them")
            }
            result = cropped
        }
        return result
    }
}

extension Annotation {
    /// The annotation in a canvas whose origin was at `origin` and that's drawn `scale` times as big.
    func reframed(origin: CGPoint, scale: CGFloat) -> Annotation {
        let moved = self.moved(by: CGSize(width: -origin.x, height: -origin.y))
        guard scale != 1 else {
            return moved
        }
        // `scaled(by:)` goes about the centre, which then moves out from the canvas origin with everything else.
        let bounds = moved.bounds
        let scaled = moved.scaled(by: Double(scale))
        return bounds.isNull ? scaled : scaled.moved(by: CGSize(width: bounds.midX * (scale - 1), height: bounds.midY * (scale - 1)))
    }
}
#endif
