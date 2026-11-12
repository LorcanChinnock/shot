import ShotCore
import SwiftUI

/// The Export panel beside the video, from Edit › Video editor and export: the format and its options, the speed, then a
/// card pinned at the foot with the estimated size, the length and the button that exports. The title bar's Export opens it.
struct ExportPanel: View {
    let model: VideoEditorModel

    static let width: CGFloat = 272

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(VideoExportPanel.groups(for: model.options.format), id: \.self) { group(for: $0) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
            .disabled(model.isExporting)
            SummaryCard(model: model)
                .padding([.horizontal, .bottom], 16)
        }
        .sidePanel(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Export"))
        // The estimate reads frames, so it's worked out only while the panel shows.
        .task(id: model.edit) {
            await model.refreshEstimate()
        }
    }

    /// "Export" in 13 pt bold, and Reset as an accent-text link that greys out when every option is at its default.
    private var header: some View {
        HStack {
            Text("Export")
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Reset") { model.setOptions(.default) }
                .buttonStyle(PanelLinkStyle())
                .disabled(model.options.isDefault || model.isExporting)
                .themeTip("Reset", detail: "Puts the format, GIF size, mute and speed back to how new exports start.")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func group(for group: VideoExportPanel.Group) -> some View {
        switch group {
        case .format:
            section("Format") {
                ThemeSegmented(selection: option(\.format), options: [(.mp4, "MP4"), (.gif, "GIF")])
                    .fillingWidth()
                    .themeTip("Export format")
                    .accessibilityLabel(Text("Format"))
            }
        case .frameRate:
            section("Frames per second") {
                ThemeSegmented(selection: option(\.gifFrameRate), options: VideoExportOptions.gifFrameRates.map { ($0, "\($0)") })
                    .fillingWidth()
                    .themeTip("GIF frames per second")
                    .accessibilityLabel(Text("Frames per second"))
            }
        case .width:
            section("Width") {
                ThemeSegmented(selection: option(\.gifWidth), options: VideoExportOptions.gifWidths.map { ($0, VideoExportPanel.widthLabel($0)) })
                    .fillingWidth()
                    .themeTip("GIF width in pixels; it's never made wider than the video")
                    .accessibilityLabel(Text("Width"))
            }
        case .mute:
            HStack(spacing: 10) {
                Text("Mute")
                    .font(.scaled(12.5))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Toggle("Mute", isOn: option(\.muted))
                    .toggleStyle(ThemeToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel(Text("Mute"))
            }
            .themeTip("Leave the sound out")
        case .speed:
            section("Speed") {
                ThemeSegmented(selection: option(\.speed), options: VideoExportOptions.speeds.map { ($0, VideoExportPanel.speedLabel($0)) })
                    .fillingWidth()
                    .disabled(speedIsLocked)
                    .themeTip(speedIsLocked ? Self.speedLockedReason : "Playback speed")
                    .accessibilityLabel(Text("Speed"))
                if speedIsLocked {
                    note(Self.speedLockedReason)
                }
            }
        }
    }

    private static let speedLockedReason: LocalizedStringResource = "Speed isn't available for an MP4 with imports, annotations or transforms. A GIF can change speed."

    private var speedIsLocked: Bool {
        VideoExportPanel.speedIsLocked(format: model.options.format, isComposite: model.isComposite)
    }

    /// A heading in 11.5 pt semibold over its control, 7 pt apart.
    private func section(_ title: LocalizedStringResource, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.scaled(11.5, weight: .semibold))
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func note(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Each change is one undo step, and is remembered for the next export and Quick Access's Export GIF.
    private func option<Value>(_ keyPath: WritableKeyPath<VideoExportOptions, Value>) -> Binding<Value> {
        Binding {
            model.options[keyPath: keyPath]
        } set: { value in
            var options = model.options
            options[keyPath: keyPath] = value
            model.setOptions(options)
        }
    }
}

/// The card at the panel's foot: the estimated size and the length, then Export GIF or Export MP4 with where the file goes.
/// While anything exports, the button gives way to its progress and Cancel.
private struct SummaryCard: View {
    let model: VideoEditorModel

    var body: some View {
        let length = VideoExportPanel.length(of: model.keptLength, options: model.options, isComposite: model.isComposite)
        VStack(spacing: 10) {
            row("Estimated size") {
                Text(verbatim: model.estimatedSize.map { "≈ " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "≈ …")
                    .font(.scaled(12, weight: .bold, design: .monospaced, tabular: true))
            }
            .themeTip("Estimated size of the exported file")
            row("Length") {
                Text(verbatim: Timecode.string(length.seconds))
                    .font(.scaled(12, design: .monospaced, tabular: true))
            }
            if length.truncated {
                Text("A GIF keeps the first \(Int(GIFExporter.maxDuration)) seconds.")
                    .font(Theme.caption)
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.isExporting {
                exporting
            } else {
                exportButton
            }
        }
        .padding(12)
        .depth(.group, fill: Theme.group, radius: Theme.Radius.group)
    }

    private func row(_ title: LocalizedStringResource, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.scaled(12))
                .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
            Spacer(minLength: 8)
            value()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private var exportButton: some View {
        VStack(spacing: 10) {
            Button { Task { await model.export() } } label: {
                Text(title)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            // The panel's button is the next step once it's open; in crop mode the crop bar's Apply is (rule 1).
            .buttonStyle(ThemeButtonStyle(model.isCropping ? .secondary : .main))
            .themeTip(title, detail: detail)
            Text("Saved beside the recording and copied")
                .font(Theme.caption)
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Exporting…" with the bar while a GIF reports how far it's got, and Cancel.
    private var exporting: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Exporting…")
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let fraction = model.exportFraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.scaled(12, design: .monospaced, tabular: true))
                        .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .accessibilityElement(children: .combine)
            if let fraction = model.exportFraction {
                ThemeProgressBar(value: fraction)
            }
            Button { model.cancelExport() } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(ThemeButtonStyle())
            .themeTip("Cancel", key: "esc", detail: "Stops exporting.")
        }
    }

    private var title: LocalizedStringResource {
        if model.options.format == .gif {
            "Export GIF"
        } else {
            "Export MP4"
        }
    }

    private var detail: LocalizedStringResource {
        if model.options.format == .gif {
            "Writes a new GIF with these options next to the recording, and copies it."
        } else {
            "Writes a new MP4 with these options next to the recording, and copies it."
        }
    }
}
