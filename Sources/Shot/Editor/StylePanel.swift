import ShotCore
import SwiftUI

/// The Style panel beside the canvas, from Edit › Image editor · style. With nothing selected it styles the screenshot:
/// its background, padding, corners, shadow, border and size, and whether new captures start that way. With an image,
/// shape, arrow or text selected, that selection's corners, shadow and border come first, and the canvas's background,
/// padding and size follow. Pointing at a shadow or border tile shows it on the canvas; clicking it applies it.
struct StylePanel: View {
    @Bindable var model: EditorModel

    static let width: CGFloat = 288
    /// The panel's width less its 16 pt sides, which the sliders fill.
    private static let inner: CGFloat = width - 32

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let kind = model.targetStyleKind
        let sections = StylePanelLayout.sections(
            kind: kind, windowShadow: model.targetHasWindowShadow,
            borders: kind.map { !$0.borders(transparent: model.targetHasTransparency).isEmpty } ?? false
        )
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if kind != nil, kind != .capture {
                        groupTitle(Text(verbatim: kind?.panelTitle ?? ""))
                    }
                    ForEach(sections.target.filter { $0 != .newCaptures }, id: \.self) { section(for: $0) }
                    if !sections.canvas.isEmpty {
                        Divider().overlay(Theme.separator)
                        groupTitle(Text("Canvas"))
                        ForEach(sections.canvas, id: \.self) { section(for: $0) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
            if sections.target.contains(.newCaptures), let newCaptureStyle = model.newCaptureStyle {
                NewCaptureCard(isOn: newCaptureStyle, otherStyleSaved: model.newCapturesHaveOtherStyle)
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 4)
            }
        }
        .sidePanel(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Style"))
        .onDisappear {
            model.stylePreview = nil
        }
    }

    private var increased: Bool { contrast == .increased }

    /// "Style" in 13 pt bold, and Reset as an accent-text link that greys out when there's nothing to put back.
    private var header: some View {
        HStack {
            Text("Style")
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Reset") { model.resetTargetStyle() }
                .buttonStyle(PanelLinkStyle())
                .disabled(model.isTargetStyleDefault)
                .themeTip("Reset", detail: resetDetail)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var resetDetail: LocalizedStringResource {
        model.targetStyleKind == .capture
            ? "Puts the screenshot's background, padding, size, shadow, border and corners back to how a new capture starts."
            : "Puts the selection's shadow, border and corners back to how new ones start."
    }

    private func groupTitle(_ text: Text) -> some View {
        text
            .font(.scaled(12, weight: .bold))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func section(for section: StylePanelLayout.Section) -> some View {
        switch section {
        case .background: backgroundSection
        case .padding: paddingSection
        case .corners:
            // The screenshot's corners sit under its padding.
            if model.targetStyleKind != .capture {
                StyleSection(model: model, section: .corners, sliderWidth: Self.inner)
            }
        case .shadow, .border:
            StyleSection(model: model, section: section, sliderWidth: Self.inner)
        case .size: sizeSection
        case .windowShadowNote:
            note("Uses macOS window shadow")
                .themeTip("This window was captured with its own shadow, so it takes no other shadow, border or corners")
        case .noTargetNote:
            note("Select an image, shape, arrow or text, or nothing to style the screenshot.")
        case .newCaptures:
            EmptyView()
        }
    }

    private func note(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Background

    /// None, the panel's seven colours, three gradients, the desktop picture and a custom colour, 7 to a row.
    private var backgroundSection: some View {
        let doc = model.document
        let fill = doc.backgroundFill
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Background").panelHeading()
            LazyVGrid(columns: columns, spacing: 6) {
                BackgroundTile(name: String(localized: "None"), selected: fill == nil && doc.background == nil) {
                    model.setBackground(nil)
                } swatch: {
                    Checkerboard()
                }
                // JPEG has no alpha, so it can't keep transparent padding.
                .disabled(model.isJPEG)
                ForEach(BackgroundSwatches.colors.indices, id: \.self) { index in
                    let swatch = BackgroundSwatches.colors[index]
                    BackgroundTile(name: swatch.name, selected: fill == nil && doc.background == swatch.color) {
                        model.setBackground(swatch.color)
                    } swatch: {
                        swatch.color.swiftUIColor
                    }
                }
                ForEach(BackgroundFill.allCases, id: \.self) { gradient in
                    BackgroundTile(name: gradient.title, selected: fill == gradient) {
                        model.setBackgroundFill(gradient)
                    } swatch: {
                        GradientSwatch(fill: gradient, picture: gradient == .desktop ? doc.desktopPicture : nil)
                    }
                }
                CustomBackgroundTile(model: model)
            }
        }
    }

    // MARK: Padding

    private var paddingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSliderRow(
                name: "Padding", value: Double(model.canvasPadding),
                range: Double(CanvasFrame.paddings.lowerBound)...Double(CanvasFrame.paddings.upperBound),
                shown: "\(Int(model.canvasPadding.rounded())) pt", width: Self.inner,
                set: { model.setCanvasPadding(CGFloat($0)) }, editing: model.setDraggingStyle
            )
            if model.targetStyleKind == .capture, !model.targetHasWindowShadow {
                StyleSection(model: model, section: .corners, sliderWidth: Self.inner)
            }
        }
    }

    // MARK: Size

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Size").panelHeading()
            ThemeSegmented(
                selection: Binding(get: { model.document.frame.aspect }, set: { model.setCanvasAspect($0) }),
                options: CanvasAspect.allCases.map { (value: $0, label: $0.title) }
            )
            .fillingWidth()
            .accessibilityLabel(Text("Size"))
        }
    }
}

extension StyleKind {
    /// The heading over a selection's own part of the Style panel.
    var panelTitle: String {
        switch self {
        case .capture: String(localized: "Screenshot")
        case .image: String(localized: "Selected image")
        case .mark: String(localized: "Selected shape")
        case .text: String(localized: "Selected text")
        }
    }
}

/// A square background swatch. The chosen one has a 1.5 pt ink ring outside a 2 pt gap; the others an inner edge.
private struct BackgroundTile<Swatch: View>: View {
    let name: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let swatch: Swatch
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            BackgroundSwatchShape(selected: selected) { swatch }
        }
        .buttonStyle(.halo)
        .opacity(isEnabled ? 1 : 0.35)
        .themeTip(name)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The swatch's square, its edge and the ring that marks it chosen.
private struct BackgroundSwatchShape<Content: View>: View {
    let selected: Bool
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipShape(shape)
            .overlay {
                if contrast == .increased {
                    Color.clear.inkBorder(shape, width: 1, color: Theme.ink.opacity(0.6))
                } else {
                    shape.strokeBorder(backgroundSwatchEdge, lineWidth: 1)
                }
            }
            .padding(3.5)
            .overlay {
                if selected {
                    // The text colour rather than the ink line, which disappears on the dark panel.
                    Color.clear.inkBorder(RoundedRectangle(cornerRadius: Theme.Radius.control + 3.5, style: .circular), width: 1.5, color: Theme.ink)
                }
            }
            .padding(-3.5)
            .contentShape(Rectangle())
    }
}

/// A background swatch's inner edge: ink at 12%, or white at 18% in dark.
private let backgroundSwatchEdge = Color(light: Color(hex: 0x16161A).opacity(0.12), dark: .white.opacity(0.18))

/// A gradient swatch, or the desktop picture itself once it's read.
private struct GradientSwatch: View {
    let fill: BackgroundFill
    let picture: CGImage?

    var body: some View {
        if let picture {
            Image(decorative: picture, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            let (start, end) = fill.colors
            LinearGradient(
                colors: [start.swiftUIColor, end.swiftUIColor],
                startPoint: .topLeading, endPoint: fill.isVertical ? .bottomLeading : .bottomTrailing
            )
        }
    }
}

/// The see-through background: a grey and white check, 5 pt squares.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let side: CGFloat = 5
            for row in 0..<Int(ceil(size.height / side)) {
                for column in 0..<Int(ceil(size.width / side)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)), with: .color(Color(hex: 0xE4E2DD)))
                }
            }
        }
    }
}

/// A rainbow swatch for any other colour. It applies the last custom colour and opens the colour editor on it, which
/// shows the colour inside the rainbow while it's in use.
private struct CustomBackgroundTile: View {
    @Bindable var model: EditorModel
    @State private var isOpen = false

    private var custom: RGBA? {
        let doc = model.document
        guard doc.backgroundFill == nil, let background = doc.background, !BackgroundSwatches.contains(background) else {
            return nil
        }
        return background
    }

    var body: some View {
        Button(action: open) {
            BackgroundSwatchShape(selected: custom != nil || isOpen) {
                ZStack {
                    AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)
                    if let custom {
                        RoundedRectangle(cornerRadius: 3, style: .circular).fill(custom.swiftUIColor).padding(6)
                    }
                }
            }
        }
        .buttonStyle(.halo)
        .themeTip("Custom background colour")
        .accessibilityLabel(Text("Custom background colour"))
        .accessibilityAddTraits(custom != nil ? .isSelected : [])
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ColorEditor(initial: model.lastBackgroundColor ?? custom ?? RGBA(1, 1, 1), pick: model.pickBackground)
        }
    }

    private func open() {
        guard !isOpen else {
            isOpen = false
            return
        }
        model.beginColorPick()
        if let last = model.lastBackgroundColor, last != custom {
            model.pickBackground(last)
        }
        isOpen = true
    }
}

/// Use for new captures, on a white card at the panel's foot. Off while new captures still get another saved style
/// says so, since the switch alone reads as "new captures are plain".
private struct NewCaptureCard: View {
    let isOn: Binding<Bool>
    let otherStyleSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Use for new captures")
                    .font(.scaled(12.5))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Toggle("Use for new captures", isOn: isOn)
                    .toggleStyle(ThemeToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel(Text("Use for new captures"))
            }
            if otherStyleSaved {
                Text("New captures keep a different saved style.")
                    .font(Theme.caption)
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .depth(.rest, fill: Theme.group, radius: Theme.Radius.group)
        .themeTip("Use for new captures", detail: "New captures open and copy with this screenshot's background, padding, size, shadow, border and corners.")
    }
}
