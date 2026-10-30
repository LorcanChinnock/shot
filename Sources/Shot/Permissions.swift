import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum Permissions {
    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// macOS can keep reporting access as missing until the relaunch, so a second request would wipe the new grant.
    private(set) static var requestedScreenCapture = false

    // A grant made for a differently signed build, such as a local dev build, stays switched on in
    // System Settings but no longer matches this app, so macOS denies it. Clearing it lets macOS ask afresh.
    static func requestScreenCapture() {
        requestedScreenCapture = true
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot"]
        if (try? process.run()) != nil {
            process.waitUntilExit()
        }
        CGRequestScreenCaptureAccess()
    }

    /// Only Browser capture needs it, to find where a browser shows its page.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt, which has a button straight to System Settings.
    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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
