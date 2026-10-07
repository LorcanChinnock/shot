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
            window = GlassWindow.make(size: NSSize(width: 500, height: 350), title: "Shot needs Screen Recording permission") { OnboardingView() }
        }
        if let window {
            GlassWindow.present(window)
        }
    }

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

private struct OnboardingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Brutal.ink)
                    .frame(width: 46, height: 46)
                    .brutalSurface(Brutal.yellow, radius: 11, shadow: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("One permission to go").font(Brutal.title(22)).foregroundStyle(Brutal.ink)
                    Text("macOS requires Screen Recording access for every capture.")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Brutal.ink.opacity(0.65))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Step(number: 1, text: "Select Grant, or open System Settings.")
                Step(number: 2, text: "Turn on Shot under Screen & System Audio Recording.")
                Step(number: 3, text: "Relaunch Shot.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            HStack(spacing: 12) {
                Button("Grant") { Permissions.requestScreenCapture() }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.mint))
                Button("Open Settings") { Permissions.openSettings() }
                    .buttonStyle(BrutalButtonStyle())
                Spacer()
                Button("Relaunch") { Permissions.relaunch() }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, GlassWindow.titlebarHeight + 4)
        .padding([.horizontal, .bottom], Brutal.windowInset)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Brutal.ink)
                .frame(width: 22, height: 22)
                .brutalSurface(Brutal.pink, radius: 6, shadow: 2)
            Text(text).font(Brutal.label).foregroundStyle(Brutal.ink)
        }
    }
}
