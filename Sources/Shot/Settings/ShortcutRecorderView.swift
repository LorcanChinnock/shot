import AppKit
import ShotCore
import SwiftUI

struct ShortcutRecorderView: View {
    let action: ShotAction
    var color: Color
    @Setting private var encoded: String
    @State private var isRecording = false
    @State private var monitor: Any?

    init(action: ShotAction, color: Color) {
        self.action = action
        self.color = color
        _encoded = Setting(wrappedValue: action.defaultCombo(replacingSystemScreenshots: Preferences().replacesSystemScreenshots)?.encoded ?? "", PreferenceKey.hotkey(action))
    }

    private var label: String {
        if isRecording {
            return "Press keys…"
        }
        return KeyCombo(encoded: encoded)?.displayString ?? "None"
    }

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(label)
                .font(Brutal.mono)
                .tracking(1)
                .frame(minWidth: 96)
        }
        .buttonStyle(BrutalButtonStyle(color: isRecording ? color : Color.white.opacity(0.85), compact: true))
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
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
            HotkeyCenter.shared.resume()
        }
    }
}
