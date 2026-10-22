import AVFoundation
import CoreImage
import Synchronization

/// A project as AVFoundation plays and exports it: its clips on composition tracks, and a compositor that draws the video layers.
public struct ProjectComposition: @unchecked Sendable {
    public let asset: AVMutableComposition
    public let videoComposition: AVVideoComposition
    public let audioMix: AVAudioMix?
    public let duration: Double
    /// What the compositor draws in place of the annotations the project has, while one is being edited.
    public let live: LiveAnnotations
}

extension CompositionBuilder {
    /// Frame rates above this aren't kept, since the compositor draws every frame. It matches the fastest recording.
    static let maximumFrameRate: Float = 120

    /// The project as one composition, with its annotations drawn over the video.
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
                throw BuildError.cannotInsert(String(localized: "the video"))
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
                throw BuildError.cannotInsert(String(localized: "the sound"))
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
        let output = project.outputRect
        let live = LiveAnnotations()
        let notes = Dictionary(uniqueKeysWithValues: project.annotationClips.map { ($0.id, $0) })
        var instructions: [ProjectInstruction] = []
        let segments = project.videoSegments()
        for (index, segment) in segments.enumerated() {
            let start = time(segment.range.lowerBound)
            let end = index == segments.count - 1 ? max(duration, start) : time(segment.range.upperBound)
            let stack = segment.layers.compactMap { layer -> ProjectInstruction.Layer? in
                switch layer {
                case let .clip(id): layers[id].map(ProjectInstruction.Layer.picture)
                case let .annotation(id): notes[id].map(ProjectInstruction.Layer.annotation)
                }
            }
            instructions.append(ProjectInstruction(timeRange: CMTimeRange(start: start, end: end), layers: stack, live: live, canvas: canvas, output: output))
        }

        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = ProjectCompositor.self
        video.renderSize = output.size
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
        LayerGeometry.evenSize(size)
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
    enum Layer {
        case picture(ClipLayer)
        case annotation(AnnotationClip)
    }

    /// Bottom to top.
    let layers: [Layer]
    let live: LiveAnnotations
    let canvas: CGSize
    /// The part of the canvas the frame shows, in canvas pixels with y down: all of it unless the frame is cropped.
    let output: CGRect

    init(timeRange: CMTimeRange, layers: [Layer], live: LiveAnnotations, canvas: CGSize, output: CGRect? = nil) {
        self.timeRange = timeRange
        self.layers = layers
        self.live = live
        self.canvas = canvas
        self.output = output ?? CGRect(origin: .zero, size: canvas)
        let tracks = layers.compactMap { if case let .picture(layer) = $0 { layer.trackID } else { nil } }
        requiredSourceTrackIDs = Array(Set(tracks)).sorted().map { NSNumber(value: $0) }
        super.init()
    }
}

/// What a compositor did with its requests, for a test to say why a frame never came (#414). It records nothing until
/// `start` is called, so playback and export only pay for one uncontended lock per event.
final class RequestLog: Sendable {
    enum Event: Equatable, Sendable, CustomStringConvertible {
        case started(Double)
        case finished(Double)
        case cancelled(Double)
        case failed(Double)
        case cancelAll

        var description: String {
            switch self {
            case let .started(time): "started \(time)"
            case let .finished(time): "finished \(time)"
            case let .cancelled(time): "cancelled \(time)"
            case let .failed(time): "failed \(time)"
            case .cancelAll: "cancel all"
            }
        }
    }

    private let state = Mutex<[Event]?>(nil)

    /// Starts recording, dropping whatever was recorded before.
    func start() {
        state.withLock { $0 = [] }
    }

    func record(_ event: Event) {
        state.withLock { $0?.append(event) }
    }

    var events: [Event] {
        state.withLock { $0 ?? [] }
    }
}

/// Draws each frame: the canvas background, then each layer bottom to top, a picture placed by its geometry or a run of annotations
/// drawn together, so an effect acts on everything under it.
final class ProjectCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let pixelFormat = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

    /// Pixels pass through as they come, with no colour conversion, and each frame takes the colour tags of the first
    /// picture in it, so the composite looks as the recording does when it plays on its own.
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private let queue = DispatchQueue(label: "Shot.compositor", attributes: .concurrent)
    private let overlays = OverlayCache()
    private let shadows = ClipShadowCache()
    private let edges = ClipEdgeCache()
    /// Counts cancels, so a frame a seek left behind stops drawing, since AVFoundation throws it away.
    private let cancels = Mutex(0)
    /// Every request from start to end, so a cancel can wait for them.
    private let drawing = DispatchGroup()
    let requests = RequestLog()

    var sourcePixelBufferAttributes: [String: any Sendable]? { Self.pixelFormat }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { Self.pixelFormat }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let asked = cancels.withLock { $0 }
        let time = request.compositionTime.seconds
        requests.record(.started(time))
        drawing.enter()
        queue.async {
            defer { self.drawing.leave() }
            func cancelled() -> Bool {
                guard self.cancels.withLock({ $0 }) != asked else {
                    return false
                }
                request.finishCancelledRequest()
                self.requests.record(.cancelled(time))
                return true
            }
            guard let instruction = request.videoCompositionInstruction as? ProjectInstruction, let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: CocoaError(.fileReadUnknown))
                self.requests.record(.failed(time))
                return
            }
            let canvas = CGRect(origin: .zero, size: instruction.canvas)
            var image = CIImage(color: .black).cropped(to: canvas)
            var firstFrame: CVPixelBuffer?
            let (hidden, drawn, clipStyles) = instruction.live.snapshot()
            // A picture whose frame didn't come isn't drawn, so the annotations either side of it draw together.
            let stack = instruction.layers.compactMap { layer -> FrameLayers.Source<(layer: ClipLayer, frame: CVPixelBuffer)>? in
                switch layer {
                case let .annotation(clip): .annotation(clip)
                case let .picture(layer): request.sourceFrame(byTrackID: layer.trackID).map { .picture((layer, $0), layer.clip) }
                }
            }
            let layers = FrameLayers.layers(of: stack, at: time, hidden: hidden, drawn: drawn, clipStyles: clipStyles)
            for layer in layers {
                if cancelled() {
                    return
                }
                switch layer {
                case let .annotations(items):
                    image = AnnotationFrame.apply(items, to: image, canvas: canvas, context: self.context, cache: self.overlays)
                case let .picture((layer, frame), clip):
                    firstFrame = firstFrame ?? frame
                    let source = CIImage(cvPixelBuffer: frame)
                    var picture = source
                    var placed = clip
                    // Fitted by the whole picture, so a crop masks it where it is.
                    let fit = placed.size.width > 0 && placed.size.height > 0 ? min(layer.canvas.width / placed.size.width, layer.canvas.height / placed.size.height) : 0
                    var geometry = LayerGeometry.transform(for: placed, canvas: layer.canvas)
                    let sourceHeight = CGFloat(CVPixelBufferGetHeight(frame))
                    if placed.crop != nil, placed.size.width > 0, placed.size.height > 0 {
                        // Upright, y up, with its origin at the picture's bottom left, then cut to the part left, which
                        // is then drawn as a picture of its own at the place it had.
                        let kept = LayerGeometry.keptRect(of: placed)
                        let flipSource = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: sourceHeight))
                        let flipUpright = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: placed.size.height))
                        let cut = CGRect(x: kept.minX, y: placed.size.height - kept.maxY, width: kept.width, height: kept.height)
                        picture = picture.transformed(by: flipSource.concatenating(layer.orientation).concatenating(flipUpright))
                            .cropped(to: cut)
                            .transformed(by: CGAffineTransform(translationX: -cut.minX, y: -cut.minY))
                        geometry = LayerGeometry.keptTransform(for: placed, canvas: layer.canvas)
                        placed.size = kept.size
                        picture = picture.transformed(by: LayerGeometry.imageTransform(orientation: .identity, geometry: geometry, sourceHeight: kept.height, canvasHeight: canvas.height))
                    } else {
                        picture = picture.transformed(by: LayerGeometry.imageTransform(orientation: layer.orientation, geometry: geometry, sourceHeight: sourceHeight, canvasHeight: canvas.height))
                    }
                    if placed.isStyled, placed.size.width > 0, placed.size.height > 0 {
                        let placement = LayerGeometry.imageTransform(orientation: .identity, geometry: geometry, sourceHeight: placed.size.height, canvasHeight: canvas.height)
                        let lift = placed.animation.lift(at: time - placed.start)
                        image = ClipStyler.composite(
                            picture, of: placed, frame: source, time: time - placed.start, placement: placement, fit: fit, lift: lift,
                            over: image, shadows: self.shadows, edges: self.edges, context: self.context
                        )
                        continue
                    }
                    if placed.transform.opacity < 1 {
                        picture = picture.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, placed.transform.opacity)))])
                    }
                    image = picture.composited(over: image)
                }
            }
            if cancelled() {
                return
            }
            // A cropped frame shows only its part of the canvas, moved to the corner of a smaller picture.
            let shown = CGRect(x: instruction.output.minX, y: canvas.height - instruction.output.maxY, width: instruction.output.width, height: instruction.output.height)
            let framed = shown.origin == .zero ? image.cropped(to: shown) : image.cropped(to: shown).transformed(by: CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
            self.context.render(framed, to: output, bounds: CGRect(origin: .zero, size: shown.size), colorSpace: nil)
            if let tags = firstFrame.flatMap({ CVBufferCopyAttachments($0, .shouldPropagate) }) {
                CVBufferSetAttachments(output, tags, .shouldPropagate)
            }
            request.finish(withComposedVideoFrame: output)
            self.requests.record(.finished(time))
        }
    }

    /// Returns only once every request has ended, as AVFoundation's header requires. Each request checks for the
    /// cancel between layers and before the final render, so the wait is at most one of those steps.
    /// AVFoundation starts and cancels requests on one queue, so none starts during the wait.
    func cancelAllPendingVideoCompositionRequests() {
        cancels.withLock { $0 += 1 }
        drawing.wait()
        requests.record(.cancelAll)
    }
}
