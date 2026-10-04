import AVFoundation
import ShotCore
import SwiftUI

struct VideoEditorRootView: View {
    /// Everything but the player: title bar, timeline row, insets, and gaps.
    static let chromeHeight: CGFloat = GlassWindow.titlebarHeight + TrimTimelineView.height + Brutal.windowInset + Brutal.sectionGap * 1.5 + 24

    let model: VideoEditorModel

    var body: some View {
        VStack(spacing: Brutal.sectionGap) {
            HStack(spacing: 12) {
                Text(model.fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brutal.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.isDirty {
                    BrutalChip(text: "TRIMMED", color: Brutal.pink)
                }
                Spacer()
                Text(timesLabel)
                    .font(Brutal.mono)
                    .foregroundStyle(Brutal.ink.opacity(0.7))
                Button("Copy") { Task { await model.copy() } }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .help("Copy video (⌘C)")
                Button("Save") { Task { await model.save() } }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                    .help("Save trimmed video and copy it (⌘S)")
            }
            .disabled(model.isExporting)
            .padding(.leading, GlassWindow.trafficLightsWidth)
            .frame(height: GlassWindow.titlebarHeight)
            .padding(.bottom, -Brutal.sectionGap / 2)
            PlayerHost(player: model.player)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .continuous))
                .brutalSurface(Color.clear)
            HStack(spacing: 12) {
                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Brutal.ink)
                        .frame(width: 44, height: 44)
                        .brutalCircle(Brutal.yellow, shadow: 3)
                }
                .buttonStyle(.plain)
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
                .accessibilityLabel(Text(model.isPlaying ? "Pause" : "Play"))
                TrimTimelineView(model: model)
            }
        }
        .padding([.horizontal, .bottom], Brutal.windowInset)
    }

    private var timesLabel: String {
        "\(Timecode.string(model.range.start)) – \(Timecode.string(model.range.end))  ·  \(Timecode.string(model.range.length))"
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

/// Frame thumbnails with draggable in and out handles and the playhead; a drag elsewhere scrubs.
struct TrimTimelineView: View {
    static let height: CGFloat = 56

    let model: VideoEditorModel
    @State private var drag: (handle: TrimHandle?, grabOffset: CGFloat)?

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
                    if drag == nil {
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
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
