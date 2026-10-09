import AppKit
import QuartzCore
import ShotCore
import SwiftUI

/// The hidden party mode, found on the About page: rainbow accents and confetti. It only touches Shot's own UI, never a
/// capture or an export. With Reduce Motion on, the rainbow holds still and there's no confetti.
@MainActor
enum Party {
    static var isOn: Bool { Preferences().partyMode }

    static func color(at time: TimeInterval) -> Color {
        Color(hue: PartyMode.hue(at: time), saturation: 0.65, brightness: 1)
    }
}

/// Shows `content` in `color`, or in party mode in the rainbow's colour of the moment. Off, nothing here redraws.
struct PartyColor<Content: View>: View {
    let color: Color
    @ViewBuilder let content: (Color) -> Content
    @Setting(PreferenceKey.partyMode) private var party: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ color: Color, @ViewBuilder content: @escaping (Color) -> Content) {
        self.color = color
        self.content = content
    }

    var body: some View {
        if party {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                content(Party.color(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate))
            }
        } else {
            content(color)
        }
    }
}

/// Party mode's confetti, bursting out of a capture just saved.
@MainActor
enum Confetti {
    private static let colors = [Brutal.yellow, Brutal.pink, Brutal.mint, Brutal.sky, Brutal.violet, Brutal.red]

    private static let piece: CGImage? = {
        let size = CGSize(width: 8, height: 5)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()

    /// `rect` is an AppKit global rect.
    static func burst(from rect: CGRect) {
        guard Party.isOn, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main else {
            return
        }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let local = rect.intersection(screen.frame).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let emitter = CAEmitterLayer()
        emitter.frame = view.bounds
        emitter.emitterPosition = CGPoint(x: local.midX, y: local.midY)
        emitter.emitterSize = local.size
        emitter.emitterShape = .rectangle
        emitter.emitterMode = .outline
        emitter.beginTime = CACurrentMediaTime()
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = piece
            cell.color = NSColor(color).cgColor
            cell.birthRate = 60
            cell.lifetime = 3
            cell.velocity = 420
            cell.velocityRange = 180
            cell.emissionRange = .pi * 2
            cell.yAcceleration = -700
            cell.spin = 4
            cell.spinRange = 8
            cell.scaleRange = 0.4
            cell.alphaSpeed = -0.3
            return cell
        }
        view.layer?.addSublayer(emitter)
        panel.contentView = view
        panel.orderFrontRegardless()
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            emitter.birthRate = 0
            try? await Task.sleep(for: .seconds(3))
            panel.orderOut(nil)
        }
    }
}
