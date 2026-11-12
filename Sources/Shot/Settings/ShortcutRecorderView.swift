import AppKit
import ShotCore
import SwiftUI

/// An action's global shortcut in Settings › Shortcuts (Library & Settings › Settings · Shortcuts): its keys as keycaps,
/// "Record Shortcut" when it has none, and "Press keys…" in the focus halo while it listens, with the keys that cancel
/// and clear beside it. Clicking it listens; clicking again, or Esc, stops.
struct ShortcutRecorderView: View {
    let action: ShotAction
    @Setting private var encoded: String
    @State private var isRecording = false
    @State private var monitor: Any?

    init(action: ShotAction) {
        self.action = action
        _encoded = Setting(wrappedValue: action.defaultCombo(replacingSystemScreenshots: Preferences().replacesSystemScreenshots)?.encoded ?? "", PreferenceKey.hotkey(action))
    }

    private var combo: KeyCombo? { KeyCombo(encoded: encoded) }

    /// What VoiceOver reads as the shortcut's value.
    private var value: String {
        if isRecording {
            return String(localized: "Press keys…")
        }
        return combo?.displayString ?? String(localized: "None")
    }

    private var hint: LocalizedStringResource {
        isRecording ? "Press the new keys. Escape cancels and Delete clears." : "Records a new shortcut."
    }

    var body: some View {
        HStack(spacing: 12) {
            if isRecording {
                Text("Esc cancels · ⌫ clears")
                    .font(.scaled(11.5))
                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            Button {
                isRecording ? stop() : start()
            } label: {
                label
            }
            .buttonStyle(RecorderButtonStyle(state: isRecording ? .listening : combo == nil ? .empty : .set))
            .accessibilityLabel(Text("\(action.title) shortcut"))
            .accessibilityValue(Text(value))
            .accessibilityHint(Text(hint))
        }
        .onDisappear(perform: stop)
    }

    @ViewBuilder
    private var label: some View {
        if isRecording {
            Text("Press keys…")
                .font(.scaled(12.5, weight: .semibold))
        } else if let combo {
            HStack(spacing: 3) {
                ForEach(Array(combo.keycaps.enumerated()), id: \.offset) { _, key in
                    RecorderKeycap(key: key)
                }
            }
        } else {
            Text("Record Shortcut")
                .font(.scaled(12.5))
        }
    }

    private func start() {
        isRecording = true
        SettingsNavigation.shared.recordingShortcut = true
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53:
                stop()
            case 51, 117:
                encoded = ""
                stop()
            default:
                let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
                // Shift alone would hijack ordinary typing.
                guard !flags.subtracting(.shift).isEmpty else {
                    NSSound.beep()
                    return nil
                }
                let combo = KeyCombo(keyCode: UInt32(event.keyCode), eventFlags: CGEventFlags(rawValue: UInt64(flags.rawValue)))
                let prefs = Preferences()
                let bindings = ShotAction.allCases.reduce(into: [ShotAction: KeyCombo]()) { $0[$1] = prefs.hotkey(for: $1) }
                if let conflict = action.conflict(for: combo, bindings: bindings) {
                    NSSound.beep()
                    Toast.error(conflict.message(for: combo))
                } else {
                    encoded = combo.encoded
                }
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            isRecording = false
            SettingsNavigation.shared.recordingShortcut = false
            HotkeyCenter.shared.resume()
        }
    }
}

/// The recorder's three looks from the board, at least 120 pt wide and rounded at 7: keycaps on a field-fill pill with a
/// hairline edge, an empty box with a control edge and tertiary text, and, while listening, the accent at 18% in the
/// focus halo with accent text. The listening box has no ink edge, so the sidebar's selected row stays the window's one
/// ink control.
private struct RecorderButtonStyle: ButtonStyle {
    enum State {
        case set, empty, listening
    }

    let state: State
    @Environment(\.colorSchemeContrast) private var contrast

    private static let radius: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .circular)
        configuration.label
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, state == .set ? 8 : 10)
            .padding(.vertical, state == .set ? 3 : 4)
            .frame(minWidth: 120, minHeight: 24)
            .background(fill, in: shape)
            .overlay {
                Color.clear.inkBorder(shape, width: 1, color: edge)
            }
            .overlay {
                if configuration.isPressed {
                    shape.fill(Brutal.hover)
                }
            }
            .background {
                if state == .listening {
                    Color.clear
                        .inkBorder(RoundedRectangle(cornerRadius: Self.radius + 4, style: .circular), width: 4, color: Brutal.focusRing)
                        .padding(-4)
                }
            }
            .contentShape(shape)
            .fixedSize()
    }

    private var increased: Bool { contrast == .increased }

    private var fill: Color {
        switch state {
        case .set: Brutal.fieldFill
        case .empty: .clear
        case .listening: Brutal.accent.opacity(0.18)
        }
    }

    private var edge: Color {
        if increased { return Brutal.ink.opacity(0.6) }
        return state == .set ? Brutal.hairline : Brutal.controlEdge
    }

    private var foreground: Color {
        if increased { return Brutal.ink }
        switch state {
        case .set: return Brutal.ink
        case .empty: return Brutal.tertiaryText
        case .listening: return Brutal.accentText
        }
    }
}

/// One key of a set shortcut: 12 pt semibold on a white cap (the secondary fill in dark) with a control edge and a 1 pt
/// drop, as the board draws them inside the recorder.
private struct RecorderKeycap: View {
    let key: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .circular)
        let edge = contrast == .increased ? Brutal.ink.opacity(0.6) : Brutal.controlEdge
        Text(verbatim: key)
            .font(.scaled(12, weight: .semibold))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(Brutal.secondaryFill, in: shape)
            .overlay {
                Color.clear.inkBorder(shape, width: 1, color: edge)
            }
            .shadow(color: edge, radius: 0, y: 1)
            .fixedSize()
    }
}
