import AVFoundation
import ShotCore
import SwiftUI

struct VideoEditorRootView: View {
    /// Everything but the player: title bar and its hairline, timeline row, insets, and gaps.
    static let chromeHeight: CGFloat = GlassWindow.titlebarHeight + 1 + TrimTimelineView.height + ExportOptionsBar.height + Brutal.windowInset + Brutal.sectionGap * 3 + 24

    /// The least the preview is squeezed to before the tracks scroll instead.
    static let playerFloor: CGFloat = 200
    static let playButtonSize: CGFloat = 44

    let model: VideoEditorModel
    @State private var windowHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // From Edit › Video editor and export: the title bar over a hairline, as in the image editor, then the editor.
        VStack(spacing: 0) {
            VideoEditorTitleBar(model: model)
                .padding(.leading, GlassWindow.trafficLightsWidth)
                .padding(.trailing, 12)
                .frame(height: GlassWindow.titlebarHeight)
            Rectangle()
                .fill(ContrastAware(standard: Brutal.hairline, increased: Brutal.ink.opacity(0.6)))
                .frame(height: 1)
                .accessibilityHidden(true)
            content
                .padding(.top, Brutal.sectionGap)
                .padding([.horizontal, .bottom], Brutal.windowInset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { windowHeight = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            model.importMedia(urls)
            return !urls.isEmpty
        }
    }

    private var content: some View {
        VStack(spacing: Brutal.sectionGap) {
            PlayerHost(player: model.player)
                .background(Color.black)
                .overlay { TransformOverlay(model: model) }
                .overlay { AnnotationCanvas(model: model) }
                .overlay { VideoCropOverlay(model: model) }
                .overlay(alignment: .leading) { drawTools }
                .inkBorder(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular), width: 2)
            if model.isAnnotating {
                AnnotationPalette(model: model)
            }
            if model.showsTracks {
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
                        .font(.scaled(15, weight: .black))
                        .foregroundStyle(Brutal.ink)
                        .frame(width: Self.playButtonSize, height: Self.playButtonSize)
                        .brutalCircle(Brutal.yellow, shadow: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, playButtonInset)
                .brutalTip(model.isPlaying ? "Pause (Space)" : "Play (Space)")
                .accessibilityLabel(Text(model.isPlaying ? "Pause" : "Play"))
                if model.showsTracks {
                    TracksView(model: model, height: lanesHeight)
                } else {
                    TrimTimelineView(model: model)
                }
            }
            ExportOptionsBar(model: model)
        }
    }

    /// The drawing tools, over the left of the video while Draw is on.
    private var drawTools: some View {
        ZStack(alignment: .leading) {
            if model.showsDrawTools {
                DrawToolColumn(model: model)
                    .padding(.leading, 16)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: model.showsDrawTools)
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
}

/// The title bar and toolbar in one, from Edit › Video editor and export: the file and what's changed beside the traffic
/// lights, then Undo, More tools and Draw, Save or Save Copy, and Export, the one main button.
private struct VideoEditorTitleBar: View {
    let model: VideoEditorModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.fileURL.lastPathComponent)
                    .font(Brutal.label)
                    .foregroundStyle(Brutal.ink)
                    .truncationMode(.middle)
                Text(verbatim: subtitle)
                    .font(Brutal.caption)
                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .padding(.leading, 8)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            actions
        }
    }

    /// The length while nothing's changed; then "Edited", and what the edit is where it can say.
    private var subtitle: String {
        guard model.isDirty else {
            return Timecode.string(model.keptLength)
        }
        let parts = VideoEditSummary(project: model.project, recording: model.fileURL).parts.map(Self.label)
        return ([String(localized: "Edited")] + parts).joined(separator: " · ")
    }

    private static func label(_ part: VideoEditSummary.Part) -> String {
        switch part {
        case .trimmed: String(localized: "trimmed", comment: "Video editor title bar, after Edited: the recording's start or end is trimmed off.")
        case let .cuts(count): String(localized: "\(count) cuts", comment: "Video editor title bar, after Edited: sections cut out of the recording.")
        case let .annotations(count): String(localized: "\(count) annotations", comment: "Video editor title bar, after Edited: arrows, text and other marks drawn over the video.")
        case let .addedClips(count): String(localized: "\(count) clips added", comment: "Video editor title bar, after Edited: videos, sounds or pictures added from other files.")
        case .cropped: String(localized: "cropped", comment: "Video editor title bar, after Edited: the video's frame is cropped.")
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Tile(selected: false, help: "Undo", key: "⌘Z", detail: "Redo with ⇧⌘Z.", isEnabled: model.history.canUndo) {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward").font(Brutal.toolIcon)
            }
            Tile(selected: model.showsTracks, help: "More tools", key: "T", detail: "Shows the tracks under the video, with keyframes, imports and annotations.") {
                model.toggleTracks()
            } label: {
                Image(systemName: "rectangle.split.3x1").font(Brutal.toolIcon)
            }
            Button {
                model.toggleDrawing()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(Brutal.toolIcon)
                    Text("Draw").font(.scaled(12, weight: .semibold))
                }
                .padding(.horizontal, 3)
            }
            .buttonStyle(BrutalButtonStyle(.toolbar, isOn: model.showsDrawTools))
            .brutalTip("Draw", detail: "Draw arrows, shapes, text, blur and more over the video.")
            Rectangle()
                .fill(Brutal.controlEdge)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 6)
                .accessibilityHidden(true)
            Group {
                if model.isExporting {
                    Button("Cancel") { model.cancelExport() }
                        .buttonStyle(BrutalButtonStyle())
                        .brutalTip("Cancel", detail: "Stops exporting.")
                } else {
                    saveButton
                }
                Button("Export") { Task { await model.export() } }
                    // In crop mode the crop bar's Apply is the next step, so Export steps back to keep one main button (rule 1).
                    .buttonStyle(BrutalButtonStyle(model.isCropping ? .secondary : .main))
                    .disabled(model.isExporting)
                    .brutalTip(String(localized: "Export"), detail: exportDetail)
            }
            .padding(.leading, 4)
        }
        .fixedSize()
    }

    @ViewBuilder private var saveButton: some View {
        if model.isComposite {
            Button("Save Copy") { Task { await model.save() } }
                .buttonStyle(BrutalButtonStyle())
                .brutalTip("Save Copy", key: "⌘S", detail: "Writes the edit as a new video next to the recording and copies it.")
        } else {
            Button("Save") { Task { await model.save() } }
                .buttonStyle(BrutalButtonStyle())
                .brutalTip("Save", key: "⌘S", detail: "Saves the trimmed video and copies it. The original goes to the Trash.")
        }
    }

    private var exportDetail: String {
        model.options.format == .gif
            ? String(localized: "Writes a new GIF with these options next to the recording, and copies it.")
            : String(localized: "Writes a new MP4 with these options next to the recording, and copies it.")
    }
}

/// Format, GIF size and frame rate, mute, speed, and the size Export would write.
struct ExportOptionsBar: View {
    static let height: CGFloat = 32

    let model: VideoEditorModel

    var body: some View {
        HStack(spacing: 12) {
            BrutalSegmented(selection: option(\.format), options: [(.mp4, "MP4"), (.gif, "GIF")])
                .brutalTip("Export format")
            if model.options.format == .gif {
                caption("FPS")
                BrutalSegmented(selection: option(\.gifFrameRate), options: VideoExportOptions.gifFrameRates.map { ($0, "\($0)") })
                    .brutalTip("GIF frames per second")
                caption("WIDTH")
                BrutalSegmented(selection: option(\.gifWidth), options: VideoExportOptions.gifWidths.map { ($0, Self.widthLabel($0)) })
                    .brutalTip("GIF width in pixels; it's never made wider than the video")
            } else {
                caption("MUTE")
                Toggle("Mute", isOn: option(\.muted))
                    .toggleStyle(BrutalToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel(Text("Mute"))
                    .brutalTip("Leave the sound out")
            }
            caption("SPEED")
            BrutalSegmented(selection: option(\.speed), options: VideoExportOptions.speeds.map { ($0, Self.speedLabel($0)) })
                .disabled(speedIsLocked)
                .overlay {
                    if speedIsLocked {
                        Color.clear.contentShape(Rectangle()).onTapGesture { Toast.error(Self.speedLockedReason) }
                    }
                }
                .brutalTip(speedIsLocked ? Self.speedLockedReason : "Playback speed")
            Spacer(minLength: 8)
            Text(model.estimatedSize.map { "≈ " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "≈ …")
                .font(Brutal.mono)
                .foregroundStyle(Brutal.faded(0.7))
                .fixedSize()
                .brutalTip("Estimated size of the exported file")
            Button("Reset") { model.setOptions(.default) }
                .buttonStyle(BrutalButtonStyle(.plain))
                .disabled(model.options.isDefault)
                .brutalTip("Puts the format, GIF size, mute and speed back to how new exports start.")
        }
        .frame(height: Self.height)
        .disabled(model.isExporting)
        .task(id: model.edit) {
            await model.refreshEstimate()
        }
    }

    private static let speedLockedReason: LocalizedStringResource = "Speed isn't available for an MP4 with imports, annotations or transforms. A GIF can change speed."

    private var speedIsLocked: Bool { model.isComposite && model.options.format == .mp4 }

    private func caption(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .sectionCaption()
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
        width == VideoExportOptions.originalWidth ? String(localized: "Full") : "\(width)"
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

    // A clear plain view would otherwise let a click on the video, or on the handles over it, drag the window.
    override var mouseDownCanMoveWindow: Bool { false }

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
                        .inkBorder(Rectangle(), width: 2, color: Brutal.pink)
                        .frame(width: max(0, timeline.x(for: cut.upperBound) - x), height: Self.height)
                        .offset(x: x)
                }
                if let selection = model.selection {
                    let x = timeline.x(for: model.project.sourceTime(atTimeline: selection.lowerBound))
                    Rectangle().fill(Brutal.sky.opacity(0.35))
                        .inkBorder(Rectangle(), width: 2, color: Brutal.sky)
                        .frame(width: max(0, timeline.x(for: model.project.sourceTime(atTimeline: selection.upperBound)) - x), height: Self.height)
                        .offset(x: x)
                }
                Color.clear.inkBorder(Rectangle(), width: 3, color: Brutal.yellow)
                    .frame(width: max(0, endX - startX), height: Self.height)
                    .offset(x: startX)
                handle(symbol: "chevron.compact.left")
                    .offset(x: startX - inset)
                handle(symbol: "chevron.compact.right")
                    .offset(x: endX)
                PlayheadCapsule(model: model, timeline: timeline, time: \.currentTime, height: Self.height + 8)
                    .offset(y: -4)
            }
            // Offsets don't size a stack, so without this it ends at the strip and the out handle, past it, can't be grabbed.
            .frame(width: geometry.size.width, height: Self.height, alignment: .topLeading)
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
        .modifier(TimelineAccessibility(model: model, label: Text("Trim timeline")))
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
        .clipShape(RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular))
    }

    private func handle(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.scaled(12, weight: .black))
            .foregroundStyle(Brutal.ink)
            .frame(width: TrimTimeline.handleWidth, height: Self.height)
            .inkOnFill(Brutal.yellow)
            .background(Brutal.yellow)
            .inkBorder(Rectangle(), width: 2)
    }
}
