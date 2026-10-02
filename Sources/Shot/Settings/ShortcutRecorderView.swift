import AppKit
import ShotCore
import SwiftUI

struct ShortcutRecorderView: View {
    let action: ShotAction
    @AppStorage private var encoded: String
    @State private var isRecording = false
    @State private var monitor: Any?

    init(action: ShotAction) {
        self.action = action
        _encoded = AppStorage(wrappedValue: action.defaultCombo.encoded, PreferenceKey.hotkey(action))
    }

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? "Type shortcut…" : KeyCombo(encoded: encoded)?.displayString ?? "None")
                .frame(minWidth: 110)
        }
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
                guard !flags.isEmpty else {
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
