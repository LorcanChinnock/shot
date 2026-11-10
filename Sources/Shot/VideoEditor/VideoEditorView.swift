import AVFoundation
import ShotCore
import SwiftUI

struct VideoEditorRootView: View {
    /// Everything but the video: the title bar and its hairline, the well's room above and below the video, the controls
    /// area with a plain recording's lanes, and the export options.
    static let chromeHeight: CGFloat = GlassWindow.titlebarHeight + 1 + VideoWell.verticalInset * 2 + PlaybackControls.areaHeight + ExportOptionsBar.height + exportPadding * 2

    /// The least the video is squeezed to before the lanes scroll instead.
    static let playerFloor: CGFloat = 200
    /// Above and below the export options, which line up with the controls area at the sides.
    private static let exportPadding: CGFloat = 10

    let model: VideoEditorModel
    @State private var windowHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // From Edit › Video editor and export: the title bar over a hairline, the video in its well, then the controls area.
        VStack(spacing: 0) {
            VideoEditorTitleBar(model: model)
                .padding(.leading, GlassWindow.trafficLightsWidth)
                .padding(.trailing, 12)
                .frame(height: GlassWindow.titlebarHeight)
            Rectangle()
                .fill(ContrastAware(standard: Brutal.hairline, increased: Brutal.ink.opacity(0.6)))
                .frame(height: 1)
                .accessibilityHidden(true)
            well
            if model.isAnnotating {
                AnnotationPalette(model: model)
                    .padding(.horizontal, PlaybackControls.side)
                    .padding(.vertical, Brutal.sectionGap / 2)
            }
            if model.showsInspector {
                ClipInspector(model: model)
                    .padding(.horizontal, PlaybackControls.side)
                    .padding(.vertical, Brutal.sectionGap / 2)
            }
            controls
            ExportOptionsBar(model: model)
                .padding(.horizontal, PlaybackControls.side)
                .padding(.vertical, Self.exportPadding)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { windowHeight = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            model.importMedia(urls)
            return !urls.isEmpty
        }
    }

    /// The video, centred in the well at its own shape with tiny corners and a soft shadow, and the drawing tools beside it.
    private var well: some View {
        GeometryReader { geometry in
            let rect = VideoWell.videoRect(showing: model.shownFrame.size, in: geometry.size)
            let corners = RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular)
            PlayerHost(player: model.player)
                .background(Color.black)
                .clipShape(corners)
                .inkBorder(corners, width: 1, color: Color(light: Brutal.line.opacity(0.08), dark: .clear))
                .shadow(color: Color(light: Brutal.line.opacity(0.16), dark: .black.opacity(0.5)), radius: 16, y: 12)
                .overlay { TransformOverlay(model: model) }
                .overlay { AnnotationCanvas(model: model) }
                .overlay { VideoCropOverlay(model: model) }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .frame(minHeight: Self.playerFloor + VideoWell.verticalInset * 2)
        .background(VideoEditorSurface.well, ignoresSafeAreaEdges: [])
        .overlay(alignment: .leading) { drawTools }
        .clipped()
    }

    /// Play, the time and the timeline's actions over the lanes, on the controls area's own surface.
    private var controls: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(VideoEditorSurface.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PlaybackControls.gap) {
                PlaybackControls(model: model)
                TracksView(model: model, height: lanesHeight)
            }
            .padding(.top, PlaybackControls.top)
            .padding(.horizontal, PlaybackControls.side)
            .padding(.bottom, PlaybackControls.bottom)
        }
        .background(VideoEditorSurface.controls, ignoresSafeAreaEdges: [])
    }

    /// The drawing tools, 16 pt in from the well's left edge while Draw is on.
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

    /// The lanes' height: all of them, unless the window is too short to leave the video `playerFloor`.
    private var lanesHeight: CGFloat {
        let layout = TracksView.layout(for: model.project)
        let everythingElse = Self.chromeHeight + model.tracksExtraHeight - layout.height
        return layout.visibleHeight(available: windowHeight - everythingElse - Self.playerFloor, minimum: TracksView.baseHeight)
    }
}

/// The title bar and toolbar in one, from Edit › Video editor and export: the file and what's changed beside the traffic
/// lights, then Undo and Draw, Save or Save Copy, and Export, the one main button.
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
