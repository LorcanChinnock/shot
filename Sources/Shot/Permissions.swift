import AppKit
import CoreGraphics

@MainActor
enum Permissions {
    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() }

    // A grant made for a differently signed build, such as a local dev build, stays switched on in
    // System Settings but no longer matches this app, so macOS denies it. Clearing it lets macOS ask afresh.
    static func requestScreenCapture() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot"]
        if (try? process.run()) != nil {
            process.waitUntilExit()
        }
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            Toast.error("Couldn't relaunch Shot. Quit and open it again.")
        }
    }
}
