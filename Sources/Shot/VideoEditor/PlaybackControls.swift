import ShotCore
import SwiftUI

/// The surfaces under the video editor's title bar, from Edit › Video editor and export.
enum VideoEditorSurface {
    /// The well the video sits in.
    static let well = Color(light: Color(hex: 0xECEAE5), dark: Color(hex: 0x151517))
    /// The controls area: the playback row and the lanes.
    static let controls = Color(light: .white, dark: Color(hex: 0x1F1F22))
    /// The hairline over the controls area.
    static let hairline = ContrastAware(standard: Brutal.hairline, increased: Brutal.ink.opacity(0.6))
}

/// The row over the lanes, from Edit › Video editor and export: Play, the playhead's time, Split, Cut, Trim idle and Add
/// media, then snapping and zoom. In a narrow window, or at a larger text size, the actions drop their names.
struct PlaybackControls: View {
    static let height: CGFloat = 30
    /// The controls area's padding: 10 above, 14 at the sides and below, with 10 between the row and the lanes.
    static let top: CGFloat = 10
    static let side: CGFloat = 14
    static let bottom: CGFloat = 14
    static let gap: CGFloat = 10

    /// The controls area's height with a plain recording's lanes: its hairline, padding, this row and the lanes.
    static let areaHeight: CGFloat = 1 + top + height + gap + TracksView.baseHeight + bottom

    let model: VideoEditorModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(named: true)
            row(named: false)
        }
        .frame(height: Self.height)
        .disabled(model.isExporting)
    }

    private func row(named: Bool) -> some View {
        HStack(spacing: 8) {
            playButton
            PlaybackTime(model: model)
                .padding(.horizontal, 6)
            divider
            actions(named: named)
            Spacer(minLength: 8)
            snap
            divider
            zoom
        }
    }

    private var playButton: some View {
        Button {
            model.togglePlay()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.scaled(12, weight: .semibold))
                .frame(width: 16, height: 24)
        }
        // Export is the screen's ink button, so Play is a plain bordered one in light and dark (rule 1).
        .buttonStyle(BrutalButtonStyle(.popUp))
        .brutalTip(model.isPlaying ? "Pause" : "Play", key: "Space")
        .accessibilityLabel(Text(model.isPlaying ? "Pause" : "Play"))
    }

    private var divider: some View {
        Rectangle()
            .fill(Brutal.controlEdge)
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }

    private func actions(named: Bool) -> some View {
        HStack(spacing: 2) {
            action("Split", symbol: "scissors", named: named) { model.split() }
                .brutalTip("Split", key: "S", detail: "Splits the clip at the playhead.")
            action("Cut", symbol: "trash", named: named) {
                _ = model.cutSelection() || model.deleteSelectedClip()
            }
            .disabled(model.selection == nil && model.selectedClipID == nil)
            .brutalTip("Cut", key: "⌫", detail: "Cuts out the selected section or clip and closes the gap. Shift-drag along the lanes to select a section.")
            trimIdleButton(named: named)
            AddMediaMenu(model: model, named: named)
        }
    }

    private func action(_ title: LocalizedStringResource, symbol: String, named: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            label(title, symbol: symbol, named: named)
        }
        .buttonStyle(BrutalButtonStyle(.toolbar))
        .accessibilityLabel(Text(title))
    }

    private func trimIdleButton(named: Bool) -> some View {
        Button {
            Task { await model.trimIdleTime() }
        } label: {
            if model.isFindingIdleTime {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    if named {
                        Text("Trim idle")
                    }
                }
            } else {
                label("Trim idle", symbol: "clock", named: named)
            }
        }
        .buttonStyle(BrutalButtonStyle(.toolbar))
        .disabled(!model.canTrimIdleTime)
        .brutalTip("Trim idle", detail: "Trims the still start and end of the recording, keeping any speech. It works while the edit is only trims and cuts.")
        .accessibilityLabel(Text("Trim idle"))
    }

    private var snap: some View {
        Button { model.toggleSnapping() } label: { Image(systemName: "arrow.right.and.line.vertical.and.arrow.left").font(Brutal.toolIcon) }
            .buttonStyle(BrutalButtonStyle(.toolbar, isOn: model.snapping))
            .brutalTip("Snap", key: "N", detail: "Snaps the playhead and dragged clips to clip edges.")
            .accessibilityLabel(Text("Snap"))
    }

    private var zoom: some View {
        HStack(spacing: 2) {
            Button { model.zoom(bySteps: -1) } label: { Image(systemName: "minus").font(Brutal.toolIcon) }
                .buttonStyle(BrutalButtonStyle(.toolbar))
                .brutalTip("Zoom out", key: "⌘−")
                .accessibilityLabel(Text("Zoom out"))
            BrutalSlider(value: Binding {
                TimelineZoom.sliderPosition(for: model.zoom)
            } set: {
                model.setZoom(TimelineZoom.zoom(atSliderPosition: $0))
            }, width: 80)
            .brutalTip("Zoom", key: "⌘0", detail: "Fits the whole recording in the timeline again.")
            .accessibilityLabel(Text("Zoom"))
            Button { model.zoom(bySteps: 1) } label: { Image(systemName: "plus").font(Brutal.toolIcon) }
                .buttonStyle(BrutalButtonStyle(.toolbar))
                .brutalTip("Zoom in", key: "⌘+")
                .accessibilityLabel(Text("Zoom in"))
        }
    }

    @ViewBuilder
    private func label(_ title: LocalizedStringResource, symbol: String, named: Bool) -> some View {
        if named {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(Brutal.toolIcon)
                Text(title)
            }
        } else {
            Image(systemName: symbol).font(Brutal.toolIcon)
        }
    }
}

/// "0:02.40 / 0:10.50": the playhead and the edit's length. It alone reads the playhead, so playback redraws just it.
private struct PlaybackTime: View {
    let model: VideoEditorModel

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: Timecode.string(model.playhead))
                .foregroundStyle(Brutal.ink)
            Text(verbatim: " / " + Timecode.string(model.keptLength))
                .fontWeight(.medium)
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
        }
        .font(.scaled(13, weight: .bold, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Playhead"))
        .accessibilityValue(Text("\(Timecode.string(model.playhead)) of \(Timecode.string(model.keptLength))"))
    }
}

/// Add media: puts video or sound files on the timeline, on new lanes at the playhead or at the end of the recording.
private struct AddMediaMenu: View {
    let model: VideoEditorModel
    let named: Bool

    var body: some View {
        BrutalDropdown(title: "Add media", entries: [
            .item("Add Video or Audio at Playhead…") { pick(appendToMain: false) },
            .item("Add Video to End…") { pick(appendToMain: true) },
        ]) {
            if named {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(Brutal.toolIcon)
                    Text("Add media")
                }
            } else {
                Image(systemName: "plus").font(Brutal.toolIcon)
            }
        }
        .buttonStyle(BrutalButtonStyle(.toolbar))
        .fixedSize()
        .brutalTip("Add media", detail: "Adds video or sound files to the timeline, at the playhead or after the recording. You can also drop them on the window.")
    }

    private func pick(appendToMain: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio]
        panel.allowsMultipleSelection = true
        panel.message = appendToMain ? String(localized: "Choose videos to add to the end") : String(localized: "Choose videos or audio to add at the playhead")
        guard panel.runModal() == .OK else {
            return
        }
        model.importMedia(panel.urls, appendToMain: appendToMain)
    }
}
