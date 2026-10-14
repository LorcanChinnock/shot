import AppKit
import os
import ServiceManagement
import ShotCore
import SwiftUI

private let log = Logger.shot("welcome")

/// The first-launch window: Screen Recording access, the macOS screenshot keys and Open at login, then a first capture.
/// Closing it never changes anything on the Mac.
@MainActor
enum WelcomeWindow {
    static let size = NSSize(width: 520, height: 360)
    private static var window: NSWindow?
    private static var model: WelcomeModel?
    private static var closeObserver: NSObjectProtocol?

    /// Saved by `loadProgress()` at launch, so it's always there afterwards.
    static var progress: OnboardingProgress {
        OnboardingProgress(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.onboarding) ?? "") ?? .done
    }

    /// Works out and saves the progress. Call first at launch: launch saves `gaveBackTextCaptureKey` every time, which
    /// would make a first launch look like an earlier user's. Reads the saved domain, since `UserDefaults` also answers
    /// with registered defaults.
    static func loadProgress() {
        let saved = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:)) ?? [:]
        let progress = OnboardingProgress(saved: saved[PreferenceKey.onboarding] as? String, hasSavedSettings: Preferences.hasSavedSettings(saved.keys))
        UserDefaults.standard.set(progress.rawValue, forKey: PreferenceKey.onboarding)
        log.notice("Onboarding: \(progress.rawValue, privacy: .public)")
    }

    /// Opens the steps still to do, at launch or after a capture fails: all of them for someone new, otherwise Screen
    /// Recording access while it's missing.
    static func showIfNeeded() {
        let steps = progress.steps(hasPermission: Permissions.hasScreenCapture)
        if !steps.isEmpty {
            show(steps, replay: false)
        }
    }

    /// Opens it again from Settings or `shot://welcome`, starting from the current settings. Closing it changes nothing.
    static func showAgain() {
        show(OnboardingProgress.replaySteps(hasPermission: Permissions.hasScreenCapture), replay: true)
    }

    /// Called when a capture finishes, so the Try it step can say it worked.
    static func captureFinished() {
        guard let model, let window, model.step == .tryIt, !model.captured else {
            return
        }
        model.captured = true
        GlassWindow.present(window)
    }

    private static func show(_ steps: [OnboardingStep], replay: Bool) {
        if let window {
            GlassWindow.present(window)
            return
        }
        let model = WelcomeModel(steps: steps, replay: replay)
        let window = GlassWindow.make(size: size, title: String(localized: "Welcome to Shot")) { WelcomeView(model: model) }
        self.model = model
        self.window = window
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { closed() }
        }
        GlassWindow.present(window)
    }

    static func close() {
        window?.close()
    }

    /// Someone new closing it at the setup step is done with it, and macOS keeps its keys. Login items are left alone.
    private static func closed() {
        if let model {
            model.stop()
            if !model.replay, model.step == .setup, progress == .new {
                SystemShortcuts.useShot(false)
                markDone()
                log.notice("Welcome closed at setup; macOS keeps its screenshot keys")
            }
        }
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        model = nil
        window = nil
    }

    fileprivate static func markDone() {
        UserDefaults.standard.set(OnboardingProgress.done.rawValue, forKey: PreferenceKey.onboarding)
    }
}

@MainActor
@Observable
private final class WelcomeModel {
    let steps: [OnboardingStep]
    let replay: Bool
    var index = 0
    var hasPermission = Permissions.hasScreenCapture
    /// Set once Grant or Open Settings sent the user to System Settings. macOS can report access only after a
    /// relaunch, so from then on the step asks for one rather than waiting for the check below.
    var visitedSettings = false
    /// Set once Grant has asked. It clears Shot's entry first, so a second Grant would wipe a grant made since.
    var requestedAccess = false
    var usesSystemKeys: Bool
    var opensAtLogin: Bool
    var captured = false
    @ObservationIgnored private var permissionCheck: Task<Void, Never>?

    var step: OnboardingStep { steps[index] }

    init(steps: [OnboardingStep], replay: Bool) {
        self.steps = steps
        self.replay = replay
        // Someone new sees the defaults; opened again, it shows what's set now.
        usesSystemKeys = replay ? Preferences().replacesSystemScreenshots : true
        opensAtLogin = replay ? SMAppService.mainApp.status == .enabled : true
        if steps.first == .permission {
            // Only while the window is open, so access granted in System Settings shows up without a click.
            permissionCheck = Task { [weak self] in
                while !Task.isCancelled, let self, !self.hasPermission {
                    try? await Task.sleep(for: .seconds(1))
                    self.hasPermission = Permissions.hasScreenCapture
                }
            }
        }
    }

    func stop() {
        permissionCheck?.cancel()
    }

    func next() {
        if index < steps.count - 1 {
            index += 1
        } else {
            WelcomeWindow.close()
        }
    }

    /// Applies both choices, then moves on to Try it.
    func finishSetup() {
        SystemShortcuts.useShot(usesSystemKeys)
        let service = SMAppService.mainApp
        if opensAtLogin != (service.status == .enabled) {
            do {
                if opensAtLogin {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                log.error("Open at login failed: \(error.localizedDescription, privacy: .public)")
                Toast.error("Couldn't change whether Shot opens at login: \(error.localizedDescription)")
            }
        }
        WelcomeWindow.markDone()
        next()
    }
}

private struct WelcomeView: View {
    let model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch model.step {
            case .permission: PermissionStep(model: model)
            case .setup: SetupStep(model: model)
            case .tryIt: TryItStep(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, GlassWindow.titlebarHeight + 4)
        .padding([.horizontal, .bottom], Brutal.windowInset)
        .overlay(alignment: .top) {
            if model.steps.count > 1 {
                StepDots(count: model.steps.count, current: model.index)
                    .frame(height: GlassWindow.titlebarHeight)
            }
        }
    }
}

private struct PermissionStep: View {
    let model: WelcomeModel

    var body: some View {
        if model.hasPermission {
            Header(symbol: "checkmark", color: Brutal.mint, title: "Access granted", subtitle: "Relaunch Shot to start capturing.")
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Relaunch") { Permissions.relaunch() }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow))
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            if model.visitedSettings {
                Header(symbol: "arrow.clockwise", color: Brutal.yellow, title: "Relaunch to finish", subtitle: "Once Shot is on in System Settings, macOS applies it after a relaunch.")
            } else {
                Header(symbol: "lock.open.fill", color: Brutal.yellow, title: "One permission to go", subtitle: "macOS requires Screen Recording access for every capture.")
            }
            VStack(alignment: .leading, spacing: 10) {
                Instruction(number: 1, text: model.requestedAccess ? "Open System Settings." : "Click Grant, or open System Settings.")
                Instruction(number: 2, text: "Turn on Shot under Screen & System Audio Recording.")
                Instruction(number: 3, text: "Relaunch Shot.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                // Only Grant puts Shot in the System Settings list, so Open Settings leaves it. Once it has asked, it
                // goes: macOS can keep reporting access as missing until the relaunch, and asking again would wipe the grant.
                if !model.requestedAccess {
                    Button("Grant") {
                        Permissions.requestScreenCapture()
                        model.requestedAccess = true
                        model.visitedSettings = true
                    }
                        .buttonStyle(BrutalButtonStyle(color: Brutal.mint))
                }
                Button("Open System Settings") {
                    Permissions.openSettings()
                    model.visitedSettings = true
                }
                    .buttonStyle(BrutalButtonStyle())
                Spacer()
                Button("Relaunch") { Permissions.relaunch() }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct SetupStep: View {
    @Bindable var model: WelcomeModel

    /// The keys Shot uses when macOS keeps its own.
    private var ownKeys: String {
        let keys = [ShotAction.captureFullscreen, .captureArea, .record].compactMap { $0.defaultCombo(replacingSystemScreenshots: false)?.displayString }
        return keys.formatted(.list(type: .and))
    }

    private var keysSubtitle: LocalizedStringResource {
        model.usesSystemKeys
            ? "macOS's own screenshot shortcuts turn off while Shot runs, and come back when it quits."
            : "macOS keeps its shortcuts, and Shot uses \(ownKeys) instead."
    }

    var body: some View {
        Header(symbol: "keyboard.fill", color: Brutal.pink, title: "Make it yours", subtitle: "Two choices, both in Settings later.")
        VStack(spacing: 0) {
            ToggleRow(
                title: "Use Shot for ⌘⇧3 to ⌘⇧5",
                subtitle: keysSubtitle,
                isOn: $model.usesSystemKeys, color: Brutal.pink
            )
            ToggleRow(title: "Open Shot at login", subtitle: "So your shortcuts work after a restart.", isOn: $model.opensAtLogin, color: Brutal.pink, divider: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .glassCard()
        Spacer(minLength: 0)
        HStack(spacing: 12) {
            Text("Using Claude Code, Codex or Cursor? Shot can hand them your captures.")
                .font(Brutal.caption)
                .foregroundStyle(Brutal.faded(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Button("Agents") { MainWindowController.showSettings(section: .agents) }
                .buttonStyle(BrutalButtonStyle(color: SettingsSection.agents.color, compact: true))
            Spacer(minLength: 8)
            Button("Continue") { model.finishSetup() }
                .buttonStyle(BrutalButtonStyle(color: Brutal.yellow))
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct TryItStep: View {
    let model: WelcomeModel

    var body: some View {
        let prefs = Preferences()
        if model.captured {
            Header(symbol: "party.popper.fill", color: Brutal.mint, title: "That's it", subtitle: "A few more things worth knowing.")
            VStack(alignment: .leading, spacing: 8) {
                Tip(symbol: "macwindow", text: "Press Space while you pick an area to capture a window instead.")
                if let record = prefs.hotkey(for: .record) {
                    Tip(symbol: "record.circle", text: "\(record.displayString) records an area of the screen.")
                }
                if prefs.quickAccessAfterCapture {
                    Tip(symbol: "rectangle.on.rectangle", text: "Drag the card in the corner into any app, or click the pencil to annotate.")
                }
                Tip(symbol: "menubar.rectangle", text: "Everything else is in the Shot icon in the menu bar.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") { WelcomeWindow.close() }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow))
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            Header(symbol: "camera.viewfinder", color: Brutal.sky, title: "Try it", subtitle: "Take your first screenshot.")
            Group {
                if let area = prefs.hotkey(for: .captureArea) {
                    Text("Press \(Text(area.displayString).font(Brutal.title(17))), then drag out any area.")
                } else {
                    Text("Click the Shot icon in the menu bar, then Capture Area, and drag out any area.")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Brutal.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Skip") { WelcomeWindow.close() }
                    .buttonStyle(BrutalButtonStyle())
            }
        }
    }
}

private struct Header: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Brutal.ink)
                .frame(width: 46, height: 46)
                .brutalSurface(color, radius: 11, shadow: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Brutal.title(22)).foregroundStyle(Brutal.ink)
                Text(subtitle).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Brutal.faded(0.65))
            }
        }
    }
}

private struct Instruction: View {
    let number: Int
    let text: LocalizedStringResource

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Brutal.ink)
                .frame(width: 22, height: 22)
                .brutalSurface(Brutal.pink, radius: Brutal.Radius.chip, shadow: 2)
            Text(text).font(Brutal.label).foregroundStyle(Brutal.ink)
        }
    }
}

private struct Tip: View {
    let symbol: String
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 18)
            Text(text).font(Brutal.label).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Brutal.ink)
    }
}

/// Which step this is, centred in the title bar.
private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Brutal.ink : Brutal.ink.opacity(0.2))
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(current + 1) of \(count)"))
    }
}
