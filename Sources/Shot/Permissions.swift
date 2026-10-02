import AppKit
import CoreGraphics
import SwiftUI

@MainActor
enum Permissions {
    private static var window: NSWindow?

    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() }

    static func showOnboardingIfNeeded() {
        guard !hasScreenCapture else {
            return
        }
        showOnboarding()
    }

    static func showOnboarding() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Shot needs Screen Recording permission"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView())
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

private struct OnboardingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shot captures your screen, so macOS requires Screen Recording permission.")
            Text("1. Select Grant, or open System Settings and turn on Shot.\n2. Relaunch Shot.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Grant") { CGRequestScreenCaptureAccess() }
                Button("Open Settings") { Permissions.openSettings() }
                Spacer()
                Button("Relaunch") { Permissions.relaunch() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
