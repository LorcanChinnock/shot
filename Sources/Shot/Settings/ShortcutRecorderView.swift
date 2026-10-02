import AppKit
import ShotCore
import SwiftUI

struct ShortcutRecorderView: View {
    let action: ShotAction
    var color: Color
    @AppStorage private var encoded: String
    @State private var isRecording = false
    @State private var monitor: Any?

    init(action: ShotAction, color: Color) {
        self.action = action
        self.color = color
        _encoded = AppStorage(wrappedValue: action.defaultCombo.encoded, PreferenceKey.hotkey(action))
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
                var modifiers: UInt32 = 0
                if flags.contains(.command) { modifiers |= KeyCombo.command }
                if flags.contains(.shift) { modifiers |= KeyCombo.shift }
                if flags.contains(.option) { modifiers |= KeyCombo.option }
                if flags.contains(.control) { modifiers |= KeyCombo.control }
                encoded = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers).encoded
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
