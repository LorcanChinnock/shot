import AppKit
import ShotCore
import SwiftUI

/// What sits along the canvas's foot, from Edit › Image editor · annotate: the zoom control and the Canvas menu at the
/// bottom left, and the hint at the bottom right, each 16 pt in. The hint gives way first when the canvas is narrow.
struct CanvasFoot: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView

    static let inset: CGFloat = 16

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            CanvasZoomControl(model: model, canvas: canvas)
            // Until the Canvas menu finds its place (#1099).
            CanvasPill { CanvasMenu(model: model) }
            Spacer(minLength: 12)
            CanvasHintPill(hint: model.canvasHint)
                .layoutPriority(-1)
        }
        .padding(Self.inset)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { model.canvasFootHeight = $0 }
    }
}

/// The board's small floating surface: 90% white (dark `#2C2C30` at 92%) with a hairline edge, solid in the group colour
/// with a 60% ink edge under Increase Contrast or Reduce Transparency.
private struct CanvasPillSurface: ViewModifier {
    var lifted = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular)
        let dark = scheme == .dark
        content
            .background(solid ? AnyShapeStyle(Brutal.group) : AnyShapeStyle(Self.fill), in: shape)
            .overlay {
                if contrast == .increased {
                    Color.clear.inkBorder(shape, width: 1, color: Brutal.ink.opacity(0.6))
                } else {
                    shape.strokeBorder(dark ? Color.white.opacity(0.12) : Color(hex: 0x16161A).opacity(0.1), lineWidth: dark ? 0.5 : 1)
                }
            }
            .shadow(color: lifted ? (dark ? .black.opacity(0.3) : Color(hex: 0x16161A).opacity(0.08)) : .clear, radius: 4, y: 2)
    }

    private static let fill = Color(light: .white.opacity(0.9), dark: Color(hex: 0x2C2C30).opacity(0.92))

    private var solid: Bool { contrast == .increased || reduceTransparency }
}

/// A pill of controls on the canvas, 3 pt around them.
private struct CanvasPill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .modifier(CanvasPillSurface())
    }
}

/// − · 86% · + · Fit. The percentage opens the zoom menu, for Actual Size; pinch and the shortcuts work as before.
private struct CanvasZoomControl: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView

    var body: some View {
        CanvasPill {
            Button { canvas.zoomOut() } label: {
                Image(systemName: "minus").font(.scaled(12, weight: .semibold))
            }
            .buttonStyle(BrutalButtonStyle(.toolbar))
            .disabled(!ZoomControl.canZoomOut(model.zoom))
            .brutalTip("Zoom Out", key: "⌘−")
            BrutalDropdown(title: "Zoom", entries: [
                .item("Zoom In", shortcut: "⌘+") { canvas.zoomIn() },
                .item("Zoom Out", shortcut: "⌘−") { canvas.zoomOut() },
                .divider,
                .item("Zoom to Fit", shortcut: "⌘0") { canvas.zoomToFit() },
                .item("Actual Size", shortcut: "⌘1") { canvas.zoomToActualSize() },
            ]) {
                Text("\(ZoomControl.percent(model.zoom))%")
                    .font(.scaled(12, tabular: true))
                    .foregroundStyle(Brutal.ink)
                    .frame(minWidth: 44)
            }
            .buttonStyle(BrutalButtonStyle(.toolbar))
            .accessibilityValue(Text("\(ZoomControl.percent(model.zoom))%"))
            .brutalTip("Zoom", detail: "Pinch, or scroll with ⌘ held, to zoom. Scroll, Space-drag or press H to move around. Actual Size is ⌘1.")
            Button { canvas.zoomIn() } label: {
                Image(systemName: "plus").font(.scaled(12, weight: .semibold))
            }
            .buttonStyle(BrutalButtonStyle(.toolbar))
            .disabled(!ZoomControl.canZoomIn(model.zoom))
            .brutalTip("Zoom In", key: "⌘+")
            Button("Fit") { canvas.zoomToFit() }
                .buttonStyle(BrutalButtonStyle(.toolbar))
                .brutalTip("Zoom to Fit", key: "⌘0")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Zoom"))
    }
}

/// What's selected or what the tool does, and the keys that change it. VoiceOver hears it as it changes.
private struct CanvasHintPill: View {
    let hint: CanvasHint
    @Environment(\.textSize) private var textSize
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(attributed)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .modifier(CanvasPillSurface(lifted: false))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: hint.spoken))
            .onChange(of: hint.spoken) {
                AccessibilityNotification.Announcement(hint.spoken).post()
            }
    }

    private var increased: Bool { contrast == .increased }

    /// "Arrow selected · ⌫ delete · ⇧ snap 45°", with each key in 11 pt mono.
    private var attributed: AttributedString {
        let textFont = ScaledFont.scaled(12).resolved(textSize)
        let keyFont = ScaledFont.scaled(11, design: .monospaced).resolved(textSize)
        func run(_ string: String, font: Font, color: Color) -> AttributedString {
            var run = AttributedString(string)
            run.font = font
            run.foregroundColor = color
            return run
        }
        let text = increased ? Brutal.ink : Brutal.secondaryText
        let key = increased ? Brutal.ink : Self.keyColor
        var result = run(hint.lead, font: textFont, color: text)
        for part in hint.parts {
            result += run(" · ", font: textFont, color: text)
            if let symbol = part.key?.symbol {
                result += run(symbol, font: keyFont, color: key)
                result += run(" ", font: textFont, color: text)
            }
            result += run(part.action, font: textFont, color: text)
        }
        return result
    }

    /// The board's keys: the hint's grey in light, and the ink in dark, where they stand out from it.
    private static let keyColor = Color(light: Color(hex: 0x55545A), dark: Color(hex: 0xEDEBE6))
}

/// Fit to Content, Trim to Image and Background…, until the Canvas menu moves (#1099). Background… opens the Style
/// panel, where the background now lives.
private struct CanvasMenu: View {
    @Bindable var model: EditorModel

    var body: some View {
        BrutalDropdown(title: "Canvas", entries: [
            .item("Fit to Content") { model.fitToContent() },
            .item("Trim to Image", enabled: model.document.canTrimToImage) { model.trimToImage() },
            .divider,
            .item("Background…") { model.showStylePanel() },
        ]) {
            HStack(spacing: 5) {
                Text("Canvas")
                Image(systemName: "chevron.down")
                    .font(.scaled(9, weight: .bold))
                    .foregroundStyle(ContrastAware(standard: Brutal.secondaryText, increased: Brutal.ink))
            }
        }
        .buttonStyle(BrutalButtonStyle(.toolbar))
        .fixedSize()
        .brutalTip("Canvas", detail: "Fit the canvas to what's on it, trim it to the image, or choose its background in the Style panel.")
    }
}

// MARK: Backdrop

/// Holds the canvas over its backdrop, which the canvas tells where the image is.
final class EditorCanvasContainer: NSView {
    private let backdrop = EditorCanvasBackdrop()
    private let canvas: EditorCanvasView

    init(canvas: EditorCanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        addSubview(backdrop)
        addSubview(canvas)
        canvas.onImageRectChange = { [weak self] rect in
            guard let self else {
                return
            }
            backdrop.imageRect = backdrop.convert(rect, from: self.canvas)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        canvas.frame = bounds
    }
}

/// The canvas's backdrop, from Edit › Image editor · annotate: `#ECEAE5` (dark `#151517`) with a 16 pt grid of 1 pt dots,
/// and the image's soft shadow. It's a layer apart from the canvas, so the shadow's blur is drawn once by the GPU rather
/// than on every frame of a drag.
private final class EditorCanvasBackdrop: NSView {
    var imageRect: CGRect = .null {
        didSet {
            if imageRect != oldValue {
                updateShadow()
            }
        }
    }

    private let shadowLayer = CALayer()
    private let shadowMask = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shadowMask.fillRule = .evenOdd
        shadowLayer.mask = shadowMask
        layer?.addSublayer(shadowLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        updateShadow()
    }

    override func layout() {
        super.layout()
        updateShadow()
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = isDark
        (dark ? Self.darkFill : Self.lightFill).setFill()
        dirtyRect.fill()
        (dark ? Self.darkDots : Self.lightDots).setFill()
        dirtyRect.fill()
    }

    /// `0 18px 40px`: black at 16% (dark 50%), offset down, masked to outside the image so a see-through image
    /// doesn't show it from underneath.
    private func updateShadow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowMask.frame = bounds
        if imageRect.isNull || imageRect.isEmpty {
            shadowLayer.shadowPath = nil
            shadowLayer.shadowOpacity = 0
        } else {
            let dark = isDark
            shadowLayer.shadowPath = CGPath(rect: imageRect, transform: nil)
            shadowLayer.shadowColor = dark ? NSColor.black.cgColor : Brutal.inkNS.cgColor
            shadowLayer.shadowOpacity = dark ? 0.5 : 0.16
            shadowLayer.shadowRadius = 20
            shadowLayer.shadowOffset = CGSize(width: 0, height: -18)
            let mask = CGMutablePath()
            mask.addRect(bounds.insetBy(dx: -60, dy: -60))
            mask.addRect(imageRect)
            shadowMask.path = mask
        }
        CATransaction.commit()
    }

    private static let lightFill = NSColor(srgbRed: 0xEC / 255, green: 0xEA / 255, blue: 0xE5 / 255, alpha: 1)
    private static let darkFill = NSColor(srgbRed: 0x15 / 255, green: 0x15 / 255, blue: 0x17 / 255, alpha: 1)
    private static let lightDots = dots(Brutal.inkNS.withAlphaComponent(0.08))
    private static let darkDots = dots(NSColor.white.withAlphaComponent(0.07))

    /// A 16 pt tile with a 1 pt-radius dot at its centre, as the board's `radial-gradient(… 1px, transparent 1px)`.
    private static func dots(_ color: NSColor) -> NSColor {
        NSColor(patternImage: NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 2, height: 2)).fill()
            return true
        })
    }
}
