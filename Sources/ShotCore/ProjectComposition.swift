import AVFoundation
import CoreImage

/// A project as AVFoundation plays and exports it: its clips on composition tracks, and a compositor that draws the video layers.
public struct ProjectComposition: @unchecked Sendable {
    public let asset: AVMutableComposition
    public let videoComposition: AVVideoComposition
    public let audioMix: AVAudioMix?
    public let duration: Double
    /// What the compositor draws in place of the annotations the project has, while one is being edited.
    public let live: LiveAnnotations
}

public enum CompositionBuilder {
    public enum BuildError: LocalizedError {
        case noVideo(String)
        case cannotInsert(String)

        public var errorDescription: String? {
            switch self {
            case .noVideo(let name): "\(name) has no video to show"
            case .cannotInsert(let name): "Could not add \(name) to the video"
            }
        }
    }

    /// Frame rates above this aren't kept, since the compositor draws every frame.
    static let maximumFrameRate: Float = 60

    public static func build(_ project: Project) async throws -> ProjectComposition {
        let composition = AVMutableComposition()
        var assets: [URL: AVURLAsset] = [:]
        func asset(_ url: URL) -> AVURLAsset {
            if let known = assets[url] {
                return known
            }
            let new = AVURLAsset(url: url)
            assets[url] = new
            return new
        }

        var layers: [UUID: ClipLayer] = [:]
        var frameRate: Float = 30
        for track in project.videoTracks {
            guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw BuildError.cannotInsert("the video")
            }
            for clip in track.clips {
                guard let source = try await asset(clip.source).loadTracks(withMediaType: .video).first else {
                    throw BuildError.noVideo(clip.source.lastPathComponent)
                }
                let (naturalSize, transform, rate) = try await source.load(.naturalSize, .preferredTransform, .nominalFrameRate)
                do {
                    try target.insertTimeRange(timeRange(clip.sourceStart, clip.length), of: source, at: time(clip.start))
                } catch {
                    throw BuildError.cannotInsert(clip.source.lastPathComponent)
                }
                frameRate = max(frameRate, min(rate, maximumFrameRate))
                let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
                layers[clip.id] = ClipLayer(
                    trackID: target.trackID,
                    orientation: transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)),
                    clip: clip,
                    canvas: project.canvasSize
                )
            }
        }

        var parameters: [AVMutableAudioMixInputParameters] = []
        for track in project.tracks where track.kind == .audio && !track.isMuted {
            guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw BuildError.cannotInsert("the sound")
            }
            let mix = AVMutableAudioMixInputParameters(track: target)
            for clip in track.clips {
                guard let source = try await asset(clip.source).loadTracks(withMediaType: .audio).first else {
                    continue
                }
                try target.insertTimeRange(timeRange(clip.sourceStart, clip.length), of: source, at: time(clip.start))
                setVolume(of: clip, in: mix)
            }
            parameters.append(mix)
        }

        let duration = composition.duration
        let canvas = evenSize(project.canvasSize)
        let live = LiveAnnotations()
        let notes = Dictionary(uniqueKeysWithValues: project.annotationClips.map { ($0.id, $0) })
        var instructions: [ProjectInstruction] = []
        let segments = project.videoSegments()
        for (index, segment) in segments.enumerated() {
            let start = time(segment.range.lowerBound)
            let end = index == segments.count - 1 ? max(duration, start) : time(segment.range.upperBound)
            instructions.append(ProjectInstruction(
                timeRange: CMTimeRange(start: start, end: end), layers: segment.clips.compactMap { layers[$0] },
                annotations: segment.annotations.compactMap { notes[$0] }, live: live, canvas: canvas
            ))
        }

        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = ProjectCompositor.self
        video.renderSize = canvas
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))
        video.instructions = instructions
        let audioMix: AVAudioMix? = parameters.isEmpty ? nil : {
            let mix = AVMutableAudioMix()
            mix.inputParameters = parameters
            return mix
        }()
        return ProjectComposition(asset: composition, videoComposition: video, audioMix: audioMix, duration: duration.seconds, live: live)
    }

    /// How loud a clip plays: its plain volume, or ramps through its keyframes, a tenth of a second at most to a step.
    private static func setVolume(of clip: Clip, in mix: AVMutableAudioMixInputParameters) {
        let keyframes = clip.animation.volume
        guard let first = keyframes.first, let last = keyframes.last else {
            mix.setVolume(Float(clip.volume), at: time(clip.start))
            return
        }
        mix.setVolume(Float(first.value), at: time(clip.start))
        for (from, to) in zip(keyframes, keyframes.dropFirst()) {
            let steps = max(1, Int(((to.time - from.time) / 0.1).rounded(.up)))
            for step in 0..<steps {
                let a = from.time + (to.time - from.time) * Double(step) / Double(steps)
                let b = from.time + (to.time - from.time) * Double(step + 1) / Double(steps)
                let volumeA = Keyframes.value(keyframes, at: a, base: clip.volume), volumeB = Keyframes.value(keyframes, at: b, base: clip.volume)
                mix.setVolumeRamp(fromStartVolume: Float(volumeA), toEndVolume: Float(volumeB), timeRange: CMTimeRange(start: time(clip.start + a), end: time(clip.start + b)))
            }
        }
        mix.setVolume(Float(last.value), at: time(clip.start + last.time))
    }

    /// H.264 wants even sides.
    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, (size.width / 2).rounded() * 2), height: max(2, (size.height / 2).rounded() * 2))
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private static func timeRange(_ start: Double, _ length: Double) -> CMTimeRange {
        CMTimeRange(start: time(start), duration: time(length))
    }
}

struct ClipLayer: Sendable {
    var trackID: CMPersistentTrackID
    /// Turns the source frame as stored upright, with its origin at the top left.
    var orientation: CGAffineTransform
    /// The clip, whose keyframes place the picture on the canvas at each frame.
    var clip: Clip
    var canvas: CGSize
}

final class ProjectInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    /// Keyframes make a frame depend on its time within the instruction.
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let layers: [ClipLayer]
    let annotations: [AnnotationClip]
    let live: LiveAnnotations
    let canvas: CGSize

    init(timeRange: CMTimeRange, layers: [ClipLayer], annotations: [AnnotationClip], live: LiveAnnotations, canvas: CGSize) {
        self.timeRange = timeRange
        self.layers = layers
        self.annotations = annotations
        self.live = live
        self.canvas = canvas
        requiredSourceTrackIDs = Array(Set(layers.map(\.trackID))).sorted().map { NSNumber(value: $0) }
        super.init()
    }
}

/// Draws each frame: the canvas background, then each layer's picture placed by its geometry, bottom to top.
final class ProjectCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let pixelFormat = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

    /// Pixels pass through as they come, with no colour conversion, and each frame takes the colour tags of the first
    /// picture in it, so the composite looks as the recording does when it plays on its own.
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private let queue = DispatchQueue(label: "Shot.compositor", attributes: .concurrent)
    private let overlays = OverlayCache()

    var sourcePixelBufferAttributes: [String: any Sendable]? { Self.pixelFormat }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { Self.pixelFormat }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            guard let instruction = request.videoCompositionInstruction as? ProjectInstruction, let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: CocoaError(.fileReadUnknown))
                return
            }
            let canvas = CGRect(origin: .zero, size: instruction.canvas)
            var image = CIImage(color: .black).cropped(to: canvas)
            var firstFrame: CVPixelBuffer?
            for layer in instruction.layers {
                guard let frame = request.sourceFrame(byTrackID: layer.trackID) else {
                    continue
                }
                firstFrame = firstFrame ?? frame
                var picture = CIImage(cvPixelBuffer: frame)
                var placed = layer.clip
                placed.transform = layer.clip.transform(atTimeline: request.compositionTime.seconds)
                let geometry = LayerGeometry.transform(for: placed, canvas: layer.canvas)
                let matrix = LayerGeometry.imageTransform(orientation: layer.orientation, geometry: geometry, sourceHeight: CGFloat(CVPixelBufferGetHeight(frame)), canvasHeight: canvas.height)
                picture = picture.transformed(by: matrix)
                if placed.transform.opacity < 1 {
                    picture = picture.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, placed.transform.opacity)))])
                }
                image = picture.composited(over: image)
            }
            let (hidden, drawn) = instruction.live.snapshot()
            let time = request.compositionTime.seconds
            let shown = instruction.annotations.filter { !hidden.contains($0.id) } + drawn.filter { $0.start <= time && time < $0.end }
            let items = shown.map { clip -> AnnotationFrame.Item in
                let state = clip.rendered(atTimeline: time)
                return AnnotationFrame.Item(annotation: state.annotation, rotation: state.rotation, opacity: state.opacity)
            }
            image = AnnotationFrame.apply(items, to: image, canvas: canvas, context: self.context, cache: self.overlays)
            self.context.render(image.cropped(to: canvas), to: output, bounds: canvas, colorSpace: nil)
            if let tags = firstFrame.flatMap({ CVBufferCopyAttachments($0, .shouldPropagate) }) {
                CVBufferSetAttachments(output, tags, .shouldPropagate)
            }
            request.finish(withComposedVideoFrame: output)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

public enum ProjectExporter {
    public enum ExportError: LocalizedError {
        case failed
        case unsupportedFileType

        public var errorDescription: String? {
            switch self {
            case .failed: "Could not export the video"
            case .unsupportedFileType: "Can't write this kind of video"
            }
        }
    }

    /// Writes the project to `output`, replacing it, drawn at the canvas size and re-encoded.
    public static func export(_ project: Project, to output: URL, as fileType: AVFileType = .mp4) async throws {
        let built = try await CompositionBuilder.build(project)
        guard let export = AVAssetExportSession(asset: built.asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.failed
        }
        guard export.supportedFileTypes.contains(fileType) else {
            throw ExportError.unsupportedFileType
        }
        export.videoComposition = built.videoComposition
        export.audioMix = built.audioMix
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try await export.export(to: output, as: fileType)
    }

    /// Roughly how many bytes `export` writes: a typical H.264 rate for the canvas, and AAC for any sound.
    public static func estimatedSize(of project: Project) -> Int {
        let pixels = Double(project.canvasSize.width * project.canvasSize.height)
        let hasSound = project.tracks.contains { $0.kind == .audio && !$0.isMuted && !$0.clips.isEmpty }
        let bitRate = pixels * 30 * 0.07 + (hasSound ? 128_000 : 0)
        return Int((bitRate * project.duration / 8).rounded())
    }
}
