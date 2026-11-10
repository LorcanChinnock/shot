import ShotCore
import SwiftUI

/// The project's lanes in timeline time, from Edit › Video editor and export: a mono ruler, then each lane under its name
/// in a column on the left. Annotation and picture lanes sit above the Video lane, whose clips show as a filmstrip, and sound
/// lanes below it as waveforms. Drag to scrub; drag a clip to move it and its edges to trim it; drag the yellow handles at
/// the Video lane's ends to trim; Shift-drag to select a section.
struct TracksView: View {
    static let rulerHeight: CGFloat = 14
    /// The ruler and the Video lane, which the window always has room for.
    static let baseHeight: CGFloat = rulerHeight + LaneLayout.gap + LaneLayout.mainHeight

    /// What the project's lanes add to the window's height over a recording's Video lane alone.
    static func extraHeight(for project: Project) -> CGFloat {
        layout(for: project).height - baseHeight
    }

    static func layout(for project: Project) -> LaneLayout {
        LaneLayout(project, top: rulerHeight + LaneLayout.gap)
    }

    private enum Gesture {
        case scrub
        case select(anchor: Double)
        case trimMain(TrimHandle, edge: Double)
        case move(UUID, grab: Double)
        case trim(UUID, TrimHandle)
        case keyframe(UUID, time: Double)
        /// A press on the lane names, which does nothing.
        case ignored
    }

    private struct ThumbnailRequest: Hashable {
        var source: URL
        var duration: Double
        var aspectRatio: CGFloat
        var count: Int
        var height: CGFloat
    }

    let model: VideoEditorModel
    /// How much of the lanes show; they scroll when it's less than all of them.
    let height: CGFloat
    @State private var scroll = ScrollPosition()
    @State private var scrollX: CGFloat = 0
    @State private var gesture: (kind: Gesture, startX: CGFloat, pointsPerSecond: CGFloat)?
    @State private var pinchStart: Double?
    @State private var hoveredTrack: Int?
    /// The annotation clip under the pointer, which right-clicking offers to rename.
    @State private var hoveredAnnotation: UUID?
    /// The annotation clip whose name is being edited in place.
    @State private var renaming: UUID?
    @Environment(\.textSize) private var textSize

    var body: some View {
        let layout = Self.layout(for: model.project)
        GeometryReader { geometry in
            // The lanes start right of the names; `viewWidth` is the part of the view they show in.
            let viewWidth = max(1, geometry.size.width - LaneLayout.labelWidth)
            let width = viewWidth * model.zoom
            let timeline = TrimTimeline(duration: model.fitDuration, minX: 0, width: width)
            let pointsPerSecond = width / CGFloat(max(model.fitDuration, .leastNonzeroMagnitude))
            // What was trimmed off the front shows before 0, so the lanes start that far in.
            let lead = model.project.trimmedLead
            let leadX = CGFloat(lead) * pointsPerSecond
            // Where time 0 sits in the scrolling content: past the names and what was trimmed off the front.
            let originX = LaneLayout.labelWidth + leadX
            let reach = model.project.tracks.indices.flatMap(model.project.trimmedEnds).map(\.end).max() ?? 0
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                lanes(timeline, layout: layout, leadX: leadX)
                    .offset(x: originX)
                    .frame(width: LaneLayout.labelWidth + max(width, leadX + CGFloat(reach) * pointsPerSecond), height: layout.height, alignment: .topLeading)
                    .overlay(alignment: .topLeading) { laneNames(layout).offset(x: scrollX) }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let point) = phase {
                            let track = layout.lane(at: point.y)?.track
                            hoveredTrack = track
                            let time = Double((point.x - originX) / pointsPerSecond)
                            hoveredAnnotation = track.flatMap { model.project.tracks[$0].annotations.first { time >= $0.start && time <= $0.end }?.id }
                        } else {
                            hoveredTrack = nil
                            hoveredAnnotation = nil
                        }
                    }
                    .gesture(drag(timeline, layout: layout, originX: originX))
                    .contextMenu { laneMenu }
                    .task(id: thumbnailRequests(width: width)) {
                        // Zooming and resizing change the requests many times a second, so wait for them to settle.
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else {
                            return
                        }
                        for request in thumbnailRequests(width: width) {
                            await model.loadThumbnails(of: request.source, duration: request.duration, aspectRatio: request.aspectRatio, count: request.count, height: request.height)
                        }
                    }
            }
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, new in
                scrollX = new
            }
            .onChange(of: model.zoom) { old, new in
                // Zoom around the playhead if it's in view, or the middle of the view if not.
                let oldWidth = viewWidth * CGFloat(old)
                let oldX = oldWidth * CGFloat((model.playhead + lead) / max(model.fitDuration, .leastNonzeroMagnitude)) - scrollX
                let anchor = (0...viewWidth).contains(oldX) ? oldX : viewWidth / 2
                let time = Double((scrollX + anchor) / oldWidth) * model.fitDuration
                scroll.scrollTo(x: TimelineZoom.offset(keeping: time, atViewX: anchor, duration: model.fitDuration, zoom: new, viewWidth: viewWidth))
            }
            .modifier(FollowPlayhead(model: model, scroll: $scroll, timeline: timeline, leadX: leadX, scrollX: scrollX, viewWidth: viewWidth))
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in
                    pinchStart = pinchStart ?? model.zoom
                    model.setZoom(pinchStart! * value.magnification)
                }
                .onEnded { _ in pinchStart = nil })
        }
        .frame(height: height)
        .modifier(TimelineAccessibility(model: model, label: Text("Timeline")))
        .help("Drag to scrub. Drag the yellow handles to trim, a clip to move it and its edges to trim it, and an annotation or picture up or down to restack it. Shift-drag to select a section, then press Delete to cut it. Right-click a lane for its options.")
        .allowsHitTesting(!model.isExporting)
    }

    private func thumbnailRequests(width: CGFloat) -> [ThumbnailRequest] {
        var requests: [ThumbnailRequest] = []
        for (index, track) in model.project.tracks.enumerated() where track.kind == .video {
            for clip in track.clips where clip.size.height > 0 && !requests.contains(where: { $0.source == clip.source }) {
                let height = index == 0 ? LaneLayout.mainHeight : LaneLayout.pictureHeight
                // The thumbnails are spread over the whole file, so size them for it, not for the part that's showing.
                let wholeWidth = width * clip.sourceDuration / max(model.fitDuration, .leastNonzeroMagnitude)
                let aspect = clip.size.width / clip.size.height
                requests.append(ThumbnailRequest(source: clip.source, duration: clip.sourceDuration, aspectRatio: aspect, count: min(300, TrimTimeline.thumbnailCount(width: wholeWidth, height: height, aspectRatio: aspect)), height: height))
            }
        }
        return requests
    }

    // MARK: Lanes

    /// `leadX` is where time 0 sits in the lanes.
    private func lanes(_ timeline: TrimTimeline, layout: LaneLayout, leadX: CGFloat) -> some View {
        let pointsPerSecond = timeline.width / CGFloat(max(model.fitDuration, .leastNonzeroMagnitude))
        let project = model.project
        return ZStack(alignment: .topLeading) {
            ruler(timeline, pointsPerSecond: pointsPerSecond)
            ForEach(layout.lanes, id: \.track) { lane in
                ForEach(project.tracks[lane.track].annotations) { clip in
                    annotationClip(clip, height: lane.height, pointsPerSecond: pointsPerSecond)
                        // Faded while it's dragged to another lane, where the marker shows it'll land.
                        .opacity(model.laneDrop?.clip == clip.id ? 0.4 : 1)
                        .offset(x: CGFloat(clip.start) * pointsPerSecond, y: lane.y)
                }
                ForEach(Array(project.trimmedEnds(ofTrack: lane.track).enumerated()), id: \.offset) { _, end in
                    clip(end, in: lane, pointsPerSecond: pointsPerSecond, trimmed: true)
                }
                ForEach(project.tracks[lane.track].clips) { clip in
                    self.clip(clip, in: lane, pointsPerSecond: pointsPerSecond)
                        .opacity(model.laneDrop?.clip == clip.id ? 0.4 : 1)
                }
            }
            if let preview = model.laneDrop {
                laneDropMarker(preview, layout: layout, pointsPerSecond: pointsPerSecond)
            }
            if let selection = model.selection, let main = layout.lane(ofTrack: 0) {
                let from = timeline.x(for: selection.lowerBound), to = timeline.x(for: selection.upperBound)
                Rectangle().fill(Brutal.selection.opacity(0.2))
                    .inkBorder(Rectangle(), width: 1.5, color: Brutal.selection)
                    .frame(width: max(0, to - from), height: layout.height - (layout.lanes.first?.y ?? main.y))
                    .offset(x: from, y: layout.lanes.first?.y ?? main.y)
                    .allowsHitTesting(false)
            }
            if let id = model.selectedClipID, let animation = model.selectedAnimation, let start = project.clipStart(id), let lane = layout.lane(ofTrack: trackIndex(of: id)) {
                ForEach(animation.times, id: \.self) { time in
                    diamond(selected: model.selectedKeyframe.map { abs($0 - time) <= Keyframes.tolerance } ?? false)
                        // On the lane's bottom edge, clear of the clip's name.
                        .offset(x: timeline.x(for: start + time) - 6, y: lane.y + lane.height - 6)
                }
            }
            if let main = layout.lane(ofTrack: 0), let first = project.main.clips.first, let last = project.main.clips.last {
                handle(.start, height: main.height).offset(x: timeline.x(for: first.start), y: main.y)
                handle(.end, height: main.height).offset(x: timeline.x(for: last.end) - TrimTimeline.handleWidth, y: main.y)
                ForEach(project.mainCutMarks, id: \.time) { mark in
                    // Centred on the cut in a fixed frame; an alignment guide would move the whole stack's origin.
                    CutBadge(length: mark.length)
                        .frame(width: 120)
                        .offset(x: CGFloat(mark.time) * pointsPerSecond - 60, y: main.y + 4)
                        .allowsHitTesting(false)
                }
            }
            Playhead(model: model, timeline: timeline, height: layout.height - Self.rulerHeight + 8)
                .offset(y: Self.rulerHeight - 6)
        }
    }

    /// Where a clip dragged to another lane will land: a ghost on that lane, or a bar between lanes where it'll get a new one.
    @ViewBuilder
    private func laneDropMarker(_ preview: LaneDropPreview, layout: LaneLayout, pointsPerSecond: CGFloat) -> some View {
        let project = model.project
        let x = CGFloat(preview.range.lowerBound) * pointsPerSecond
        let width = max(CGFloat(preview.range.upperBound - preview.range.lowerBound) * pointsPerSecond, 8)
        let onto: Int? = if case let .onto(track) = preview.drop, preview.result.trackID(of: preview.clip) == project.tracks[track].id { track } else { nil }
        if let onto, let lane = layout.lane(ofTrack: onto) {
            RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular)
                .fill(Brutal.yellow.opacity(0.45))
                .inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular), width: 2, dash: [4, 3])
                .frame(width: width, height: lane.height)
                .offset(x: x, y: lane.y)
                .allowsHitTesting(false)
        } else {
            let index: Int = switch preview.drop {
            case let .onto(track): track + 1
            case let .insert(track): track
            }
            // A new track at `index` goes just over the lane of the stacked track below it, or the main one.
            let below = project.stackedTrackIndices.last { $0 < index } ?? 0
            let y = layout.lane(ofTrack: below)?.y ?? 0
            Capsule().fill(Brutal.pink)
                .inkBorder(Capsule(), width: 2)
                .frame(width: width, height: 8)
                .offset(x: x, y: y - LaneLayout.gap / 2 - 4)
                .allowsHitTesting(false)
        }
    }

    /// What right-clicking a lane offers: renaming the annotation under the pointer, deleting an annotation track, and the
    /// lane's own switches.
    @ViewBuilder
    private var laneMenu: some View {
        if let id = hoveredAnnotation, model.project.annotationClip(id) != nil {
            Button("Rename") {
                model.selectClip(id)
                renaming = id
            }
            Divider()
        }
        if let index = hoveredTrack, model.project.tracks.indices.contains(index) {
            let track = model.project.tracks[index]
            ForEach(LaneControl.allCases.filter { $0.applies(to: track.kind) }, id: \.self) { control in
                Button(control.menuTitle(isOn: track[keyPath: control.flag])) { model.toggle(control.flag, ofTrack: index) }
            }
            if track.kind == .overlay {
                Divider()
                Button("Delete Track") { model.deleteTrack(index) }
            }
        }
    }

    /// Each lane's name in the column left of the lanes, pinned there as they scroll sideways, with its lock, hide and mute
    /// switches: the ones that are on, and every one while the pointer is over the lane.
    private func laneNames(_ layout: LaneLayout) -> some View {
        ZStack(alignment: .topLeading) {
            // Short of the lanes by half the playhead's cap, so the cap shows whole at 0:00.
            VideoEditorSurface.controls
                .frame(width: LaneLayout.labelWidth - 6, height: layout.height)
            ForEach(layout.lanes, id: \.track) { lane in
                let track = model.project.tracks[lane.track]
                HStack(spacing: 0) {
                    Text(Self.title(model.project.laneName(ofTrack: lane.track)))
                        .font(.scaled(10.5))
                        .foregroundStyle(ContrastAware(standard: Brutal.secondaryText, increased: Brutal.ink))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 2)
                    // The name always shows whole; at a larger text size the switches give way, and the lane's
                    // right-click menu still has them.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) {
                            ForEach(shownControls(onTrack: lane.track), id: \.self) { control in
                                laneButton(control, track: lane.track, isOn: track[keyPath: control.flag])
                            }
                        }
                        Color.clear.frame(width: 0)
                    }
                }
                .padding(.leading, 4)
                .padding(.trailing, 2)
                .frame(width: LaneLayout.labelWidth, height: lane.height)
                .offset(y: lane.y)
            }
        }
        .frame(width: LaneLayout.labelWidth, height: layout.height, alignment: .topLeading)
    }

    private static func title(_ name: LaneLayout.Name) -> LocalizedStringResource {
        switch name {
        case .draw: LocalizedStringResource("Draw", comment: "Video editor timeline: the name of a lane of arrows, shapes and other marks.")
        case .text: LocalizedStringResource("Text", comment: "Video editor timeline: the name of a lane of text annotations.")
        case .video: LocalizedStringResource("Video", comment: "Video editor timeline: the name of the recording's lane, or of an added video's.")
        case .sound: LocalizedStringResource("Sound", comment: "Video editor timeline: the name of the recording's sound lane, or of an added sound's.")
        }
    }

    private func shownControls(onTrack index: Int) -> [LaneControl] {
        let track = model.project.tracks[index]
        return LaneControl.allCases.filter { $0.applies(to: track.kind) && (hoveredTrack == index || track[keyPath: $0.flag]) }
    }

    private func laneButton(_ control: LaneControl, track: Int, isOn: Bool) -> some View {
        Button { model.toggle(control.flag, ofTrack: track) } label: {
            Image(systemName: control.symbol(isOn: isOn))
                .font(.scaled(10, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(Brutal.ink) : AnyShapeStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink)))
                .frame(width: 14, height: 16)
                .background(isOn ? Brutal.hover : .clear, in: RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalTip(control.tip(isOn: isOn))
        .accessibilityLabel(Text(control.menuTitle(isOn: isOn)))
    }

    private func ruler(_ timeline: TrimTimeline, pointsPerSecond: CGFloat) -> some View {
        let interval = TimelineRuler.interval(pointsPerSecond: pointsPerSecond)
        let ticks = TimelineRuler.ticks(duration: model.fitDuration, interval: interval)
        return Canvas { context, size in
            for time in ticks {
                let x = timeline.x(for: time)
                context.fill(Path(CGRect(x: x, y: size.height - 4, width: 1, height: 4)), with: .color(Brutal.tertiaryText.opacity(0.6)))
                context.draw(Text(TimelineRuler.label(time, interval: interval)).font(ScaledFont.scaled(10, weight: .medium, design: .monospaced).resolved(textSize)).foregroundStyle(Brutal.tertiaryText), at: CGPoint(x: x + 3, y: size.height / 2 - 1), anchor: .leading)
            }
        }
        .frame(width: timeline.width, height: Self.rulerHeight)
        .allowsHitTesting(false)
    }

    private func isSelected(_ clip: Clip) -> Bool {
        guard let selected = model.selectedClipID else {
            return false
        }
        return clip.id == selected || clip.linkedID == selected
    }

    /// A clip in its lane; `trimmed` greys out a stretch that was trimmed off it.
    private func clip(_ clip: Clip, in lane: LaneLayout.Lane, pointsPerSecond: CGFloat, trimmed: Bool = false) -> some View {
        Group {
            if model.project.tracks[lane.track].kind == .audio {
                soundClip(clip, height: lane.height, pointsPerSecond: pointsPerSecond, trimmed: trimmed)
            } else {
                pictureClip(clip, height: lane.height, pointsPerSecond: pointsPerSecond, trimmed: trimmed)
            }
        }
        .saturation(trimmed ? 0 : 1)
        .opacity(trimmed ? 0.35 : 1)
        // A point in from each end, so clips that meet, at a split or a cut, show a gap between them.
        .offset(x: CGFloat(clip.start) * pointsPerSecond + Self.clipGap, y: lane.y)
    }

    /// Half the gap between clips that meet.
    private static let clipGap: CGFloat = 1

    private func clipShape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: Brutal.Radius.control, style: .circular)
    }

    /// A clip's edge: selection blue while it's selected, a hairline otherwise.
    private func clipEdge(selected: Bool) -> (width: CGFloat, color: Color) {
        selected ? (2, Brutal.selection) : (1, Color(light: Brutal.line.opacity(0.12), dark: .white.opacity(0.2)))
    }

    private func pictureClip(_ clip: Clip, height: CGFloat, pointsPerSecond: CGFloat, trimmed: Bool) -> some View {
        let width = max(1, CGFloat(clip.length) * pointsPerSecond - Self.clipGap * 2)
        let selected = !trimmed && isSelected(clip)
        let thumbnails = model.thumbnailSets[clip.source] ?? []
        let tile = max(1, height * clip.size.width / max(clip.size.height, 1))
        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            guard !thumbnails.isEmpty else {
                return
            }
            for index in 0..<Int((size.width / tile).rounded(.up)) {
                let time = clip.sourceStart + (Double(index) + 0.5) * Double(tile / pointsPerSecond)
                let slot = min(thumbnails.count - 1, max(0, Int(time / max(clip.sourceDuration, .leastNonzeroMagnitude) * Double(thumbnails.count))))
                if let image = thumbnails[slot] {
                    context.draw(Image(decorative: image, scale: 2), in: CGRect(x: CGFloat(index) * tile, y: 0, width: tile, height: size.height))
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(clipShape())
        .inkBorder(clipShape(), width: clipEdge(selected: selected).width, color: clipEdge(selected: selected).color)
        .allowsHitTesting(false)
    }

    private func soundClip(_ clip: Clip, height: CGFloat, pointsPerSecond: CGFloat, trimmed: Bool) -> some View {
        let width = max(1, CGFloat(clip.length) * pointsPerSecond - Self.clipGap * 2)
        let selected = !trimmed && isSelected(clip)
        let waveform = model.waveforms[clip.source]
        let volume = Float(clip.volume)
        return Canvas { context, size in
            guard let waveform else {
                return
            }
            let peaks = waveform.peaks(in: clip.sourceStart..<clip.sourceEnd, count: max(1, Int(size.width / 2)))
            let mid = size.height / 2
            let barWidth = size.width / CGFloat(peaks.count)
            var path = Path()
            for (index, peak) in peaks.enumerated() {
                let x = CGFloat(index) * barWidth
                let high = min(peak.max * volume, 1), low = max(peak.min * volume, -1)
                let top = mid - CGFloat(high) * (mid - 3)
                let bottom = mid - CGFloat(low) * (mid - 3)
                path.addRect(CGRect(x: x, y: top, width: max(1, barWidth - 0.5), height: max(1, bottom - top)))
            }
            context.fill(path, with: .color(soundGreen))
        }
        .frame(width: width, height: height)
        .background(soundGreen.opacity(0.12))
        .clipShape(clipShape())
        .inkBorder(clipShape(), width: clipEdge(selected: selected).width, color: clipEdge(selected: selected).color)
        .allowsHitTesting(false)
        .task(id: clip.source) { await model.loadWaveform(for: clip.source) }
    }

    /// An annotation's span on its lane: purple with its symbol and name, or selection blue while it's selected.
    private func annotationClip(_ clip: AnnotationClip, height: CGFloat, pointsPerSecond: CGFloat) -> some View {
        let width = max(1, CGFloat(clip.duration) * pointsPerSecond - Self.clipGap * 2)
        let selected = model.selectedClipID == clip.id
        let isRenaming = renaming == clip.id
        return HStack(spacing: 5) {
            Image(systemName: clip.annotation.layerSymbol).font(.scaled(10, weight: .semibold))
            Text(clip.annotation.layerName).font(.scaled(11, weight: selected ? .semibold : .regular)).lineLimit(1)
                .opacity(isRenaming ? 0 : 1)
        }
        .foregroundStyle(selected ? Color.white : annotationText)
        .padding(.horizontal, 8)
        .frame(width: width, height: height, alignment: .leading)
        .background(selected ? Brutal.selection : annotationFill, in: clipShape())
        .clipShape(clipShape())
        .inkBorder(clipShape(), width: selected ? 1.5 : 1, color: selected ? .white : Color(light: Brutal.line.opacity(0.1), dark: .white.opacity(0.14)))
        .allowsHitTesting(false)
        .offset(x: Self.clipGap)
        // Over the clip rather than in it, so a short clip doesn't squeeze the field.
        .overlay(alignment: .leading) {
            if isRenaming {
                LayerNameField(name: clip.annotation.layerName, fontSize: 11, onCommit: { name in
                    renaming = nil
                    model.renameAnnotation(clip.id, to: name)
                }, onCancel: { renaming = nil })
                .frame(width: max(width - 24, 140))
                .padding(.leading, 22)
            }
        }
    }

    private func trackIndex(of id: UUID) -> Int {
        model.project.tracks.firstIndex { $0.clips.contains { $0.id == id } || $0.annotations.contains { $0.id == id } } ?? 0
    }

    private func diamond(selected: Bool) -> some View {
        Rectangle()
            .fill(selected ? Brutal.pink : Brutal.yellow)
            .inkBorder(Rectangle(), width: 2)
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(45))
            .frame(width: 12, height: 12)
            .allowsHitTesting(false)
    }

    /// A yellow trim handle at one end of the Video lane, rounded on its outer side, with an ink edge in light.
    private func handle(_ edge: TrimHandle, height: CGFloat) -> some View {
        let r = Brutal.Radius.control
        let shape = UnevenRoundedRectangle(topLeadingRadius: edge == .start ? r : 0, bottomLeadingRadius: edge == .start ? r : 0,
                                           bottomTrailingRadius: edge == .end ? r : 0, topTrailingRadius: edge == .end ? r : 0, style: .circular)
        return shape.fill(Brutal.yellow)
            .inkBorder(shape, width: 1.5, color: Color(light: Brutal.line, dark: .clear))
            .frame(width: TrimTimeline.handleWidth, height: height)
            .allowsHitTesting(false)
    }

    // MARK: Gestures

    /// `originX` is where time 0 sits in the scrolling content.
    private func drag(_ timeline: TrimTimeline, layout: LaneLayout, originX: CGFloat) -> some SwiftUI.Gesture {
        let pointsPerSecond = timeline.width / CGFloat(max(model.fitDuration, .leastNonzeroMagnitude))
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                if gesture == nil {
                    // The names are pinned over the content's left edge, so a press on them isn't on a lane.
                    let onNames = value.startLocation.x - scrollX < LaneLayout.labelWidth
                    let point = CGPoint(x: value.startLocation.x - originX, y: value.startLocation.y)
                    gesture = (onNames ? .ignored : start(point, timeline: timeline, layout: layout), value.startLocation.x, pointsPerSecond)
                }
                guard let gesture else {
                    return
                }
                let time = Double((value.location.x - originX) / gesture.pointsPerSecond)
                let reach = Double(Snapping.reach / gesture.pointsPerSecond)
                switch gesture.kind {
                case .scrub:
                    model.scrub(toTimeline: time, snapThreshold: reach)
                case .select(let anchor):
                    model.select(fromTimeline: anchor, toTimeline: time)
                case .trimMain(let handle, let edge):
                    model.drag(handle, to: edge + Double((value.location.x - gesture.startX) / gesture.pointsPerSecond))
                case .move(let id, let grab):
                    let drop = model.project.stackedTrackIndices.contains(trackIndex(of: id)) ? layout.laneDrop(at: value.location.y, in: model.project) : nil
                    model.moveClip(id, toStart: time - grab, snapThreshold: reach, drop: drop)
                case .trim(let id, let handle):
                    model.trimClip(id, handle, toTimeline: time, snapThreshold: reach)
                case .keyframe(let id, let original):
                    model.moveKeyframe(id, from: original, toTimeline: time)
                case .ignored:
                    break
                }
            }
            .onEnded { _ in
                switch gesture?.kind {
                case .select, .ignored:
                    gesture = nil
                    return
                default:
                    break
                }
                gesture = nil
                model.endDrag()
            }
    }

    /// What a press at `point` starts, with its side effects of pausing and selecting.
    private func start(_ point: CGPoint, timeline: TrimTimeline, layout: LaneLayout) -> Gesture {
        let pointsPerSecond = timeline.width / CGFloat(max(model.fitDuration, .leastNonzeroMagnitude))
        let time = Double(point.x / pointsPerSecond)
        let project = model.project
        let lane = layout.lane(at: point.y)
        if NSEvent.modifierFlags.contains(.shift), lane != nil {
            model.selectClip(nil as UUID?)
            return .select(anchor: min(time, project.duration))
        }
        model.beginDrag()
        model.clearSelection()
        // A diamond on the selected clip is grabbed before the clip under it.
        if let id = model.selectedClipID, let animation = model.selectedAnimation, let start = project.clipStart(id), let keyed = layout.lane(ofTrack: trackIndex(of: id)) {
            for time in animation.times where abs(point.x - timeline.x(for: start + time)) <= 8 && abs(point.y - (keyed.y + keyed.height)) <= 9 {
                model.selectKeyframe(time)
                return .keyframe(id, time: time)
            }
        }
        guard let lane else {
            return .scrub
        }
        let clip = project.tracks[lane.track].clips.first { point.x >= timeline.x(for: $0.start) && point.x <= timeline.x(for: $0.end) }
        let note = project.tracks[lane.track].annotations.first { point.x >= timeline.x(for: $0.start) && point.x <= timeline.x(for: $0.end) }
        if let note {
            // The second click of a double-click renames it; the first has selected it.
            if NSApp.currentEvent?.clickCount == 2 {
                renaming = note.id
            }
            return startEditing(note.id, start: note.start, end: note.end, point: point, timeline: timeline, time: time)
        }
        let followsMain = clip.map { picked in project.main.clips.contains { $0.linkedID == picked.id } } ?? false
        if lane.track == 0 {
            let reach = TrimTimeline.handleWidth + TrimTimeline.slop
            if let first = project.main.clips.first, let last = project.main.clips.last {
                if abs(point.x - timeline.x(for: first.start)) <= reach, point.x < timeline.x(for: first.start) + reach {
                    return .trimMain(.start, edge: first.sourceStart)
                }
                if abs(point.x - timeline.x(for: last.end)) <= reach, point.x > timeline.x(for: last.end) - reach {
                    return .trimMain(.end, edge: last.sourceEnd)
                }
            }
            model.selectClip(clip?.id)
            return .scrub
        }
        guard let clip else {
            model.selectClip(nil as UUID?)
            return .scrub
        }
        if followsMain {
            model.selectClip(clip.id)
            return .scrub
        }
        return startEditing(clip.id, start: clip.start, end: clip.end, point: point, timeline: timeline, time: time)
    }

    /// Selects a clip that isn't on the main track and starts moving it, or trimming it if the press is on an edge.
    private func startEditing(_ id: UUID, start: Double, end: Double, point: CGPoint, timeline: TrimTimeline, time: Double) -> Gesture {
        model.selectClip(id)
        let pointsPerSecond = timeline.width / CGFloat(max(model.fitDuration, .leastNonzeroMagnitude))
        let zone = min(Snapping.reach, CGFloat(end - start) * pointsPerSecond / 3)
        let reach = Snapping.reach
        if abs(point.x - timeline.x(for: start)) <= reach, point.x - timeline.x(for: start) < zone {
            return .trim(id, .start)
        }
        if abs(point.x - timeline.x(for: end)) <= reach, timeline.x(for: end) - point.x < zone {
            return .trim(id, .end)
        }
        return .move(id, grab: time - start)
    }
}

/// The playhead: a 2 pt line with a cap in the ruler, white in dark and ink in light. It alone reads the time, so playback
/// redraws just it rather than the lanes it's over.
struct Playhead: View {
    let model: VideoEditorModel
    let timeline: TrimTimeline
    let height: CGFloat

    private static let color = Color(light: Brutal.line, dark: .white)

    var body: some View {
        VStack(spacing: -2) {
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 2, style: .circular)
                .fill(Self.color)
                .frame(width: 12, height: 12)
            Rectangle()
                .fill(Self.color)
                .frame(width: 2)
        }
        .frame(width: 12, height: height)
        .shadow(color: Color(light: .clear, dark: .black.opacity(0.5)), radius: 0.5)
        .offset(x: timeline.x(for: model.playhead) - 6)
        .allowsHitTesting(false)
    }
}

/// "CUT 1.2s" on the Video lane where a cut was made: ink with light text, since a cut can be undone and record red is kept
/// for recording (rule 6).
private struct CutBadge: View {
    let length: Double

    var body: some View {
        HStack(spacing: 3) {
            Text("Cut", comment: "Video editor timeline: the badge where a section was cut out, before its length, as in CUT 1.2s.")
                .textCase(.uppercase)
            Text(verbatim: Duration.seconds(length).formatted(.units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 1))))
        }
        .font(.scaled(9.5, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Brutal.line, in: RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular))
        .fixedSize()
    }
}

/// Sound clips' waveform and tint.
private let soundGreen = Color(light: Color(hex: 0x248A3D), dark: Color(hex: 0x34C759))
/// Annotation clips' fill and text, as on the board.
private let annotationFill = Color(light: Color(hex: 0xDCD6F2), dark: Color(hex: 0x4A3D7A))
private let annotationText = Color(light: Color(hex: 0x2E2660), dark: Color(hex: 0xEDEBE6))

/// A timeline as one VoiceOver element whose value is the playhead. A modifier re-runs without re-running the view it's on,
/// so reading the time here doesn't redraw the timeline on every tick.
struct TimelineAccessibility: ViewModifier {
    let model: VideoEditorModel
    let label: Text

    func body(content: Content) -> some View {
        content
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Text("\(Timecode.string(model.playhead)) of \(Timecode.string(model.keptLength))"))
            .accessibilityAdjustableAction { model.nudgePlayhead(bySeconds: $0 == .increment ? 1 : -1) }
    }
}

/// Scrolls the lanes to keep the playhead in view while playing, as a modifier for the same reason as `TimelineAccessibility`.
private struct FollowPlayhead: ViewModifier {
    let model: VideoEditorModel
    @Binding var scroll: ScrollPosition
    let timeline: TrimTimeline
    let leadX: CGFloat
    let scrollX: CGFloat
    let viewWidth: CGFloat

    func body(content: Content) -> some View {
        content.onChange(of: model.playhead) {
            let x = timeline.x(for: model.playhead) + leadX
            if model.isPlaying, x < scrollX || x > scrollX + viewWidth - 24 {
                scroll.scrollTo(x: max(0, x - viewWidth * 0.2))
            }
        }
    }
}

/// A switch on a lane, for the kinds of track it means something on.
private enum LaneControl: CaseIterable {
    case lock, hide, mute

    var flag: WritableKeyPath<Track, Bool> {
        switch self {
        case .lock: \.isLocked
        case .hide: \.isHidden
        case .mute: \.isMuted
        }
    }

    func applies(to kind: Track.Kind) -> Bool {
        switch self {
        case .lock: true
        case .hide: kind != .audio
        case .mute: kind == .audio
        }
    }

    func symbol(isOn: Bool) -> String {
        switch self {
        case .lock: isOn ? "lock.fill" : "lock.open"
        case .hide: isOn ? "eye.slash" : "eye"
        case .mute: isOn ? "speaker.slash.fill" : "speaker.wave.2.fill"
        }
    }

    func menuTitle(isOn: Bool) -> LocalizedStringResource {
        switch self {
        case .lock: isOn ? "Unlock Track" : "Lock Track"
        case .hide: isOn ? "Show Track" : "Hide Track"
        case .mute: isOn ? "Unmute Track" : "Mute Track"
        }
    }

    func tip(isOn: Bool) -> LocalizedStringResource {
        switch self {
        case .lock: isOn ? "Unlock the track" : "Lock the track, so Split and new annotations leave it alone"
        case .hide: isOn ? "Show the track" : "Hide the track"
        case .mute: isOn ? "Unmute the track" : "Mute the track"
        }
    }
}
