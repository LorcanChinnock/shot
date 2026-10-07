import AVFoundation
import ShotCore
import SwiftUI

struct VideoEditorRootView: View {
    /// Everything but the player: title bar, timeline row, insets, and gaps.
    static let chromeHeight: CGFloat = GlassWindow.titlebarHeight + TrimTimelineView.height + ExportOptionsBar.height + Brutal.windowInset + Brutal.sectionGap * 2.5 + 24

    /// The least the preview is squeezed to before the tracks scroll instead.
    static let playerFloor: CGFloat = 200
    static let playButtonSize: CGFloat = 44

    let model: VideoEditorModel
    @State private var windowHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: Brutal.sectionGap) {
            HStack(spacing: 12) {
                Text(model.fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brutal.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.isDirty {
                    BrutalChip(text: model.cuts.isEmpty && !model.isComposite ? "TRIMMED" : "EDITED", color: Brutal.pink)
                }
                Spacer()
                Text(timesLabel)
                    .font(Brutal.mono)
                    .foregroundStyle(Brutal.ink.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Button { model.toggleTracks() } label: { Label("Tracks", systemImage: "rectangle.split.3x1").fixedSize() }
                    .buttonStyle(BrutalButtonStyle(color: model.showsTracks ? (model.canHideTracks ? Brutal.violet : Brutal.violet.opacity(0.55)) : .white, compact: true))
                    .help("Show the tracks (T)")
                Button("Copy") { Task { await model.copy() } }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .help("Copy video (⌘C)")
                Button("Export") { Task { await model.export() } }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.sky, compact: true))
                    .help("Export a new \(model.options.format.rawValue.uppercased()) with these options next to the video, and copy it")
                Button(model.isComposite ? "Save copy" : "Save") { Task { await model.save() } }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                    .help(model.isComposite ? "Write the edit as a new video next to the original and copy it (⌘S)" : "Save the edited video and copy it (⌘S)")
            }
            .disabled(model.isExporting)
            .padding(.leading, GlassWindow.trafficLightsWidth)
            .frame(height: GlassWindow.titlebarHeight)
            .padding(.bottom, -Brutal.sectionGap / 2)
            PlayerHost(player: model.player)
                .background(Color.black)
                .overlay { TransformOverlay(model: model) }
                .overlay { AnnotationCanvas(model: model) }
                .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular))
                .brutalSurface(Color.clear)
            if model.showsTracks {
                if model.isAnnotating {
                    AnnotationPalette(model: model)
                }
                TracksToolbar(model: model)
                if model.showsInspector {
                    ClipInspector(model: model)
                }
            }
            HStack(alignment: model.showsTracks ? .top : .center, spacing: 12) {
                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Brutal.ink)
                        .frame(width: Self.playButtonSize, height: Self.playButtonSize)
                        .brutalCircle(Brutal.yellow, shadow: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, playButtonInset)
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
                .accessibilityLabel(Text(model.isPlaying ? "Pause" : "Play"))
                if model.showsTracks {
                    TracksView(model: model, height: lanesHeight)
                } else {
                    TrimTimelineView(model: model)
                }
            }
            ExportOptionsBar(model: model)
        }
        .padding([.horizontal, .bottom], Brutal.windowInset)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { windowHeight = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.importMedia(urls) }
            return !urls.isEmpty
        }
    }

    /// Drops the play button so it's centred on the main track's row, which sits below the ruler and any picture or annotation lanes.
    private var playButtonInset: CGFloat {
        guard model.showsTracks, let main = TracksView.layout(for: model.project).lane(ofTrack: 0) else {
            return 0
        }
        let top = min(main.y, lanesHeight - LaneLayout.mainHeight)
        return max(0, top + (LaneLayout.mainHeight - Self.playButtonSize) / 2)
    }

    /// The lanes' height: all of it, unless the window is too short to leave the preview `playerFloor`.
    private var lanesHeight: CGFloat {
        let layout = TracksView.layout(for: model.project)
        let everythingElse = Self.chromeHeight + model.tracksExtraHeight - layout.height
        let minimum = TracksView.rulerHeight + LaneLayout.gap + LaneLayout.mainHeight
        return layout.visibleHeight(available: windowHeight - everythingElse - Self.playerFloor, minimum: minimum)
    }

    private var timesLabel: String {
        "\(Timecode.string(model.range.start)) – \(Timecode.string(model.range.end))  ·  \(Timecode.string(model.keptLength))"
    }
}

/// Format, GIF size and frame rate, mute, speed, and the size Export would write.
struct ExportOptionsBar: View {
    static let height: CGFloat = 32

    let model: VideoEditorModel

    var body: some View {
        HStack(spacing: 12) {
            BrutalSegmented(selection: option(\.format), options: [(.mp4, "MP4"), (.gif, "GIF")], color: Brutal.sky)
                .help("Export format")
            if model.options.format == .gif {
                caption("FPS")
                BrutalSegmented(selection: option(\.gifFrameRate), options: VideoExportOptions.gifFrameRates.map { ($0, "\($0)") }, color: Brutal.mint)
                    .help("GIF frames per second")
                caption("WIDTH")
                BrutalSegmented(selection: option(\.gifWidth), options: VideoExportOptions.gifWidths.map { ($0, Self.widthLabel($0)) }, color: Brutal.mint)
                    .help("GIF width in pixels; it's never made wider than the video")
            } else {
                caption("MUTE")
                Toggle("Mute", isOn: option(\.muted))
                    .toggleStyle(BrutalToggleStyle(color: Brutal.pink))
                    .labelsHidden()
                    .accessibilityLabel(Text("Mute"))
                    .help("Leave the sound out")
            }
            caption("SPEED")
            BrutalSegmented(selection: option(\.speed), options: VideoExportOptions.speeds.map { ($0, Self.speedLabel($0)) }, color: Brutal.violet)
                .disabled(speedIsLocked)
                .overlay {
                    if speedIsLocked {
                        Color.clear.contentShape(Rectangle()).onTapGesture { Toast.error(Self.speedLockedReason) }
                    }
                }
                .help(speedIsLocked ? Self.speedLockedReason : "Playback speed")
            Spacer(minLength: 8)
            Text(model.estimatedSize.map { "≈ " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "≈ …")
                .font(Brutal.mono)
                .foregroundStyle(Brutal.ink.opacity(0.7))
                .fixedSize()
                .help("Estimated size of the exported file")
        }
        .frame(height: Self.height)
        .disabled(model.isExporting)
        .task(id: model.edit) {
            await model.refreshEstimate()
        }
    }

    private static let speedLockedReason = "Speed isn't available for an MP4 with imports, annotations or transforms. A GIF can change speed."

    private var speedIsLocked: Bool { model.isComposite && model.options.format == .mp4 }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black))
            .tracking(1.2)
            .foregroundStyle(Brutal.ink.opacity(0.75))
            .fixedSize()
            .padding(.trailing, -6)
    }

    /// Each change is one undo step.
    private func option<Value>(_ keyPath: WritableKeyPath<VideoExportOptions, Value>) -> Binding<Value> {
        Binding {
            model.options[keyPath: keyPath]
        } set: { value in
            var options = model.options
            options[keyPath: keyPath] = value
            model.setOptions(options)
        }
    }

    private static func widthLabel(_ width: Int) -> String {
        width == VideoExportOptions.originalWidth ? "Full" : "\(width)"
    }

    private static func speedLabel(_ speed: Double) -> String {
        (speed.rounded() == speed ? "\(Int(speed))" : "\(speed)") + "×"
    }
}

private struct PlayerHost: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {}
}

private final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerLayer.videoGravity = .resizeAspect
        layer = playerLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Frame thumbnails with draggable in and out handles, the cuts, and the playhead; a drag elsewhere
/// scrubs, and a Shift-drag selects a section for Delete to cut.
struct TrimTimelineView: View {
    static let height: CGFloat = 56

    let model: VideoEditorModel
    @State private var drag: (handle: TrimHandle?, grabOffset: CGFloat)?
    /// Where a Shift-drag started, in seconds.
    @State private var selectionAnchor: Double?

    var body: some View {
        GeometryReader { geometry in
            let inset = TrimTimeline.handleWidth
            let timeline = TrimTimeline(duration: model.duration, minX: inset, width: max(0, geometry.size.width - inset * 2))
            let startX = timeline.x(for: model.range.start)
            let endX = timeline.x(for: model.range.end)
            let count = TrimTimeline.thumbnailCount(width: timeline.width, height: Self.height, aspectRatio: model.aspectRatio)
            ZStack(alignment: .topLeading) {
                strip(width: timeline.width)
                    .offset(x: inset)
                Rectangle().fill(Color.black.opacity(0.55))
                    .frame(width: max(0, startX - inset), height: Self.height)
                    .offset(x: inset)
                Rectangle().fill(Color.black.opacity(0.55))
                    .frame(width: max(0, timeline.minX + timeline.width - endX), height: Self.height)
                    .offset(x: endX)
                ForEach(model.cuts.cuts, id: \.self) { cut in
                    let x = timeline.x(for: cut.lowerBound)
                    Rectangle().fill(Color.black.opacity(0.7))
                        .overlay(Rectangle().strokeBorder(Brutal.pink, lineWidth: 2))
                        .frame(width: max(0, timeline.x(for: cut.upperBound) - x), height: Self.height)
                        .offset(x: x)
                }
                if let selection = model.selection {
                    let x = timeline.x(for: model.project.sourceTime(atTimeline: selection.lowerBound))
                    Rectangle().fill(Brutal.sky.opacity(0.35))
                        .overlay(Rectangle().strokeBorder(Brutal.sky, lineWidth: 2))
                        .frame(width: max(0, timeline.x(for: model.project.sourceTime(atTimeline: selection.upperBound)) - x), height: Self.height)
                        .offset(x: x)
                }
                Rectangle().strokeBorder(Brutal.yellow, lineWidth: 3)
                    .frame(width: max(0, endX - startX), height: Self.height)
                    .offset(x: startX)
                handle(symbol: "chevron.compact.left")
                    .offset(x: startX - inset)
                handle(symbol: "chevron.compact.right")
                    .offset(x: endX)
                Capsule().fill(Color.white)
                    .overlay(Capsule().strokeBorder(Brutal.ink, lineWidth: 1))
                    .frame(width: 4, height: Self.height + 8)
                    .offset(x: timeline.x(for: model.currentTime) - 2, y: -4)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if drag == nil, selectionAnchor == nil, NSEvent.modifierFlags.contains(.shift) {
                        selectionAnchor = timeline.time(at: value.startLocation.x)
                    }
                    if let selectionAnchor {
                        model.select(fromSource: selectionAnchor, toSource: timeline.time(at: value.location.x))
                        return
                    }
                    if drag == nil {
                        model.clearSelection()
                        let handle = timeline.handle(at: value.startLocation.x, range: model.range)
                        let edge = handle.map { timeline.x(for: $0 == .start ? model.range.start : model.range.end) } ?? value.startLocation.x
                        drag = (handle, edge - value.startLocation.x)
                        model.beginDrag()
                    }
                    guard let drag else {
                        return
                    }
                    let time = timeline.time(at: value.location.x + drag.grabOffset)
                    if let handle = drag.handle {
                        model.drag(handle, to: time)
                    } else {
                        model.seek(to: time)
                    }
                }
                .onEnded { _ in
                    if selectionAnchor != nil {
                        selectionAnchor = nil
                        return
                    }
                    drag = nil
                    model.endDrag()
                })
            .task(id: [Double(count), model.duration]) {
                await model.loadThumbnails(count: count, height: Self.height)
            }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(Text("Trim timeline"))
        .accessibilityValue(Text("\(Timecode.string(model.playhead)) of \(Timecode.string(model.keptLength))"))
        .accessibilityAdjustableAction { model.nudgePlayhead(bySeconds: $0 == .increment ? 1 : -1) }
        .help("Drag the handles to trim. Shift-drag to select a section, then press Delete to cut it.")
        // Save reloads the file when it finishes, which would drop a trim made meanwhile.
        .allowsHitTesting(!model.isExporting)
    }

    private func strip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(model.thumbnails.indices, id: \.self) { index in
                ZStack {
                    Color.black
                    if let image = model.thumbnails[index] {
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: width / CGFloat(max(1, model.thumbnails.count)), height: Self.height)
                .clipped()
            }
        }
        .frame(width: width, height: Self.height, alignment: .leading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .circular))
    }

    private func handle(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(Brutal.ink)
            .frame(width: TrimTimeline.handleWidth, height: Self.height)
            .background(Brutal.yellow)
            .overlay(Rectangle().strokeBorder(Brutal.ink, lineWidth: 1.5))
    }
}
