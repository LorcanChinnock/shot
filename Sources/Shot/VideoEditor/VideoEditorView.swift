import AVFoundation
import ShotCore
import SwiftUI

struct VideoEditorRootView: View {
    /// Everything but the video: the title bar and its hairline, the well's room above and below the video, and the
    /// controls area with a plain recording's lanes.
    static let chromeHeight: CGFloat = GlassWindow.titlebarHeight + 1 + VideoWell.verticalInset * 2 + PlaybackControls.areaHeight

    /// The least the video is squeezed to before the lanes scroll instead.
    static let playerFloor: CGFloat = 200

    let model: VideoEditorModel
    @State private var windowHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // From Edit › Video editor and export: the title bar over a hairline, the video in its well over the controls area, and
        // the Inspector or the Export panel beside both once one is open. They take turns, so the video keeps its room.
        VStack(spacing: 0) {
            VideoEditorTitleBar(model: model)
                .padding(.leading, GlassWindow.trafficLightsWidth)
                .padding(.trailing, 12)
                .frame(height: GlassWindow.titlebarHeight)
            Rectangle()
                .fill(ContrastAware(standard: Theme.hairline, increased: Theme.ink.opacity(0.6)))
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    well
                    controls
                }
                // The side panel sits beside the video and the controls, from under the title bar to the window's foot.
                switch model.sidePanel {
                case .inspector:
                    InspectorPanel(model: model)
                        .transition(panelTransition)
                case .export:
                    ExportPanel(model: model)
                        .transition(panelTransition)
                case nil:
                    EmptyView()
                }
            }
            .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: model.sidePanel)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { windowHeight = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            model.importMedia(urls)
            return !urls.isEmpty
        }
    }

    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    /// The video, centred in the well at its own shape with tiny corners and a soft shadow, the drawing tools beside it,
    /// the style bar over its top and, in crop mode, the crop bar at its foot.
    private var well: some View {
        GeometryReader { geometry in
            let rect = VideoWell.videoRect(showing: model.shownFrame.size, in: geometry.size, bottomClearance: model.isCropping ? model.cropBarClearance : 0)
            let corners = RoundedRectangle(cornerRadius: Theme.Radius.tiny, style: .circular)
            PlayerHost(player: model.player)
                .background(Color.black)
                .clipShape(corners)
                .inkBorder(corners, width: 1, color: Color(light: Theme.line.opacity(0.08), dark: .clear))
                .shadow(color: Color(light: Theme.line.opacity(0.16), dark: .black.opacity(0.5)), radius: 16, y: 12)
                .overlay { TransformOverlay(model: model) }
                .overlay { AnnotationCanvas(model: model) }
                .overlay { VideoCropOverlay(model: model) }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .frame(minHeight: Self.playerFloor + VideoWell.verticalInset * 2)
        .background(VideoEditorSurface.well, ignoresSafeAreaEdges: [])
        .overlay(alignment: .leading) { drawTools }
        .overlay(alignment: .top) { VideoStyleBar(model: model) }
        // In crop mode, the image editor's crop bar at the well's foot, which the video fits above.
        .overlay { CropBarOverlay(model: model) }
        .clipped()
        // Clipping hides a scaled-up clip's handles past the well, but only a content shape stops them catching clicks
        // meant for the title bar or the controls.
        .contentShape(Rectangle())
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
/// lights, then Undo, Draw and Inspector, Save or Save Copy, and Export, the one main button.
private struct VideoEditorTitleBar: View {
    let model: VideoEditorModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.fileURL.lastPathComponent)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                    .truncationMode(.middle)
                Text(verbatim: subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
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
                Image(systemName: "arrow.uturn.backward").font(Theme.toolIcon)
            }
            Button {
                model.toggleDrawing()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(Theme.toolIcon)
                    Text("Draw").font(.scaled(12, weight: .semibold))
                }
                .padding(.horizontal, 3)
            }
            .buttonStyle(ThemeButtonStyle(.toolbar, isOn: model.showsDrawTools))
            .themeTip("Draw", detail: "Draw arrows, shapes, text, blur and more over the video.")
            Tile(
                selected: model.showsInspector, help: "Inspector", key: "⌥⌘I",
                detail: "Shows a panel beside the video for the selected clip's or annotation's position, scale, keyframes and style."
            ) {
                model.toggleInspector()
            } label: {
                Image(systemName: "slider.horizontal.3").font(Theme.toolIcon)
            }
            Rectangle()
                .fill(Theme.controlEdge)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 6)
                .accessibilityHidden(true)
            Group {
                if model.isExporting {
                    Button("Cancel") { model.cancelExport() }
                        .buttonStyle(ThemeButtonStyle())
                        .themeTip("Cancel", detail: "Stops exporting.")
                } else {
                    saveButton
                }
                Button("Export") { model.toggleExportPanel() }
                    // One main button (rule 1): once the panel is open its own Export GIF or MP4 is the next step, and in
                    // crop mode the crop bar's Apply is, so Export steps back to secondary. No isOn: a secondary button's
                    // on state is the accent halo, which would read as focus and put a second yellow mark beside the panel's.
                    .buttonStyle(ThemeButtonStyle(model.isCropping || model.showsExportPanel ? .secondary : .main))
                    .accessibilityAddTraits(model.showsExportPanel ? .isSelected : [])
                    .themeTip("Export", detail: "Opens the Export panel, where you choose a GIF or an MP4 and export it.")
            }
            .padding(.leading, 4)
        }
        .fixedSize()
    }

    @ViewBuilder private var saveButton: some View {
        if model.isComposite {
            Button("Save Copy") { Task { await model.save() } }
                .buttonStyle(ThemeButtonStyle())
                .themeTip("Save Copy", key: "⌘S", detail: "Writes the edit as a new video next to the recording and copies it.")
        } else {
            Button("Save") { Task { await model.save() } }
                .buttonStyle(ThemeButtonStyle())
                .themeTip("Save", key: "⌘S", detail: "Saves the trimmed video and copies it. The original goes to the Trash.")
        }
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
