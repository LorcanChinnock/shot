import AppKit
import os
import ServiceManagement
import ShotCore
import SwiftUI

private let log = Logger.shot("welcome")

/// The first-launch window: Screen Recording and Accessibility access, the macOS screenshot keys and Open at login, then a first capture.
/// Closing it never changes anything on the Mac.
@MainActor
enum WelcomeWindow {
    /// The board's window, grown with Settings › Text size so the larger text still fits.
    static func size(_ textSize: TextSize) -> NSSize {
        let scale = CGFloat(textSize.scale)
        return NSSize(width: (808 * scale).rounded(), height: (548 * scale).rounded())
    }

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
        let steps = progress.steps(hasPermission: Permissions.hasScreenCapture, hasAccessibility: Permissions.hasAccessibility)
        if !steps.isEmpty {
            show(steps, replay: false)
        }
    }

    /// Opens it again from Settings or `shot://welcome`, starting from the current settings. Closing it changes nothing.
    static func showAgain() {
        show(OnboardingProgress.replaySteps(hasPermission: Permissions.hasScreenCapture, hasAccessibility: Permissions.hasAccessibility), replay: true)
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
        let window = GlassWindow.make(size: size(Preferences().textSize), title: String(localized: "Welcome to Shot")) { WelcomeView(model: model) }
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
    var hasAccessibility = Permissions.hasAccessibility
    /// Set once Grant or Open Settings sent the user to System Settings. macOS can report access only after a
    /// relaunch, so from then on the step asks for one rather than waiting for the check below.
    var visitedSettings = Permissions.requestedScreenCapture
    /// Set once Grant, or Allow… in Settings › About, has asked. It clears Shot's entry first, so a second Grant would
    /// wipe a grant made since.
    var requestedAccess = Permissions.requestedScreenCapture
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
        if steps.contains(where: { $0 == .permission || $0 == .accessibility }) {
            // Only while the window is open, so access granted in System Settings shows up without a click.
            permissionCheck = Task { [weak self] in
                while !Task.isCancelled, let self {
                    try? await Task.sleep(for: .seconds(1))
                    self.hasPermission = Permissions.hasScreenCapture
                    self.hasAccessibility = Permissions.hasAccessibility
                }
            }
        }
    }

    func stop() {
        permissionCheck?.cancel()
    }

    var canGoBack: Bool { index > 0 }

    /// Back to the step before, which the board's footer offers. Nothing is undone: Continue on setup applies its
    /// choices again.
    func back() {
        if canGoBack {
            index -= 1
        }
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

/// Library & Settings › Welcome: the steps in the title bar, the step's title, words and controls on the left, a picture
/// on the right, and its buttons along the bottom with Back on the left.
private struct WelcomeView: View {
    let model: WelcomeModel

    var body: some View {
        Group {
            switch model.step {
            case .permission: PermissionStep(model: model)
            case .accessibility: AccessibilityStep(model: model)
            case .setup: SetupStep(model: model)
            case .tryIt: TryItStep(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            StepIndicator(items: OnboardingIndicatorItem.items(steps: model.steps, current: model.index, finished: model.step == .tryIt && model.captured))
                .frame(height: GlassWindow.titlebarHeight)
        }
    }
}

/// One step's layout, the same for every step as the board's Make it yours.
private struct StepPage<Content: View, Picture: View, Leading: View, Trailing: View>: View {
    let model: WelcomeModel
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    @ViewBuilder let content: Content
    @ViewBuilder let picture: Picture
    @ViewBuilder var leading: Leading
    @ViewBuilder let trailing: Trailing
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(Theme.display)
                        .tracking(-0.56)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                    Text(subtitle)
                        .font(.scaled(14))
                        .lineSpacing(3)
                        .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                        .fixedSize(horizontal: false, vertical: true)
                    content
                        .padding(.top, 10)
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                picture
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            .padding(.top, GlassWindow.titlebarHeight + 22)
            .padding(.horizontal, 48)
            .frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: 8) {
                if model.canGoBack {
                    Button("Back") { model.back() }
                        .buttonStyle(ThemeButtonStyle(.plain, large: true))
                        .fixedSize()
                }
                leading
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        // VoiceOver starts each step at its title.
        .onAppear { titleFocused = true }
    }
}

extension StepPage where Leading == EmptyView {
    init(
        model: WelcomeModel,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        @ViewBuilder content: () -> Content,
        @ViewBuilder picture: () -> Picture,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(model: model, title: title, subtitle: subtitle, content: content, picture: picture, leading: { EmptyView() }, trailing: trailing)
    }
}

private struct PermissionStep: View {
    let model: WelcomeModel

    private var title: LocalizedStringResource {
        if model.hasPermission {
            "Access granted"
        } else if model.visitedSettings {
            "Relaunch to finish"
        } else {
            "One permission to go"
        }
    }

    private var subtitle: LocalizedStringResource {
        if model.hasPermission {
            "Relaunch Shot to start capturing."
        } else if model.visitedSettings {
            "Once Shot is on in System Settings, macOS applies it after a relaunch."
        } else {
            "macOS requires Screen Recording access for every capture."
        }
    }

    var body: some View {
        StepPage(model: model, title: title, subtitle: subtitle) {
            if !model.hasPermission {
                SettingsCard {
                    Instruction(number: 1, text: model.requestedAccess ? "Open System Settings." : "Click Grant, or open System Settings.")
                    Instruction(number: 2, text: "Turn on Shot under Screen & System Audio Recording.")
                    Instruction(number: 3, text: "Relaunch Shot.")
                }
            }
        } picture: {
            PermissionPicture(list: "Screen & System Audio Recording", isOn: model.hasPermission)
        } leading: {
            if !model.hasPermission {
                Button("Open System Settings") {
                    Permissions.openSettings()
                    model.visitedSettings = true
                }
                .buttonStyle(ThemeButtonStyle(large: true))
                .fixedSize()
            }
        } trailing: {
            // Only Grant puts Shot in the System Settings list, so Open Settings leaves it. Once it has asked, it goes:
            // macOS can keep reporting access as missing until the relaunch, and asking again would wipe the grant.
            let asks = !model.hasPermission && !model.requestedAccess
            Button("Relaunch") { Permissions.relaunch() }
                .buttonStyle(ThemeButtonStyle(asks ? .secondary : .main, large: true))
                .keyboardShortcut(asks ? nil : .defaultAction)
                .fixedSize()
            if asks {
                Button("Grant") {
                    Permissions.requestScreenCapture()
                    model.requestedAccess = true
                    model.visitedSettings = true
                }
                .buttonStyle(ThemeButtonStyle(.main, large: true))
                .keyboardShortcut(.defaultAction)
                .fixedSize()
            }
        }
    }
}

private struct AccessibilityStep: View {
    let model: WelcomeModel

    var body: some View {
        StepPage(
            model: model,
            title: model.hasAccessibility ? "Browser pages are ready" : "Capture just the web page",
            subtitle: model.hasAccessibility
                ? "Shot can now find the page in a browser window. Turn on Capture only the page in browser windows in Settings to use it."
                : "Capturing only the page in a browser window needs Accessibility access to find where the browser shows its page. Skip it if you'll capture whole windows."
        ) {
            if !model.hasAccessibility {
                SettingsCard {
                    Instruction(number: 1, text: "Click Grant, then Open System Settings.")
                    Instruction(number: 2, text: "Turn on Shot under Accessibility.")
                }
            }
        } picture: {
            PermissionPicture(list: "Accessibility", isOn: model.hasAccessibility)
        } trailing: {
            if model.hasAccessibility {
                Button("Continue") { model.next() }
                    .buttonStyle(ThemeButtonStyle(.main, large: true))
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
            } else {
                Button("Skip") { model.next() }
                    .buttonStyle(ThemeButtonStyle(.plain, large: true))
                    .fixedSize()
                Button("Grant") { Permissions.requestAccessibility() }
                    .buttonStyle(ThemeButtonStyle(.main, large: true))
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
            }
        }
    }
}

private struct SetupStep: View {
    @Bindable var model: WelcomeModel

    /// The keys Shot uses when macOS keeps its own.
    private var ownKeys: String {
        let keys = [ShotAction.screenshot, .record].compactMap { $0.defaultCombo(replacingSystemScreenshots: false)?.displayString }
        return keys.formatted(.list(type: .and))
    }

    private var keysSubtitle: LocalizedStringResource {
        model.usesSystemKeys
            ? "macOS gets its screenshot keys back when Shot quits."
            : "macOS keeps its shortcuts, and Shot uses \(ownKeys) instead."
    }

    var body: some View {
        StepPage(model: model, title: "Make it yours", subtitle: "Two choices. You can change both later in Settings.") {
            SettingsCard {
                ToggleRow(title: "Use Shot for ⌘⇧4 and ⌘⇧5", subtitle: keysSubtitle, isOn: $model.usesSystemKeys)
                ToggleRow(title: "Open Shot at login", subtitle: "So your shortcuts work after a restart.", isOn: $model.opensAtLogin)
            }
        } picture: {
            ShortcutPicture(usesSystemKeys: model.usesSystemKeys)
        } trailing: {
            Button("Continue") { model.finishSetup() }
                .buttonStyle(ThemeButtonStyle(.main, large: true))
                .keyboardShortcut(.defaultAction)
                .fixedSize()
        }
    }
}

private struct TryItStep: View {
    let model: WelcomeModel
    @Environment(\.textSize) private var textSize

    var body: some View {
        let prefs = Preferences()
        let area = prefs.hotkey(for: .screenshot)
        if model.captured {
            StepPage(model: model, title: "That's it", subtitle: "A few more things worth knowing.") {
                SettingsCard {
                    Tip(symbol: "macwindow", text: "Press Tab while you pick an area to choose a window or the full screen instead.")
                    if let record = prefs.hotkey(for: .record) {
                        Tip(symbol: "record.circle", text: "\(record.displayString) records the screen the same way.")
                    }
                    if prefs.quickAccessAfterCapture {
                        Tip(symbol: "rectangle.on.rectangle", text: "Drag the card in the corner into any app, or click the pencil to annotate.")
                    }
                    Tip(symbol: "menubar.rectangle", text: "Everything else is in the Shot icon in the menu bar.")
                }
            } picture: {
                TryItPicture(keys: area?.keycaps, captured: true)
            } trailing: {
                Button("Done") { WelcomeWindow.close() }
                    .buttonStyle(ThemeButtonStyle(.main, large: true))
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
            }
        } else {
            StepPage(model: model, title: "Try it", subtitle: "Take your first screenshot.") {
                SettingsCard {
                    Group {
                        if let area {
                            Text("Press \(Text(area.displayString).font(Theme.label.resolved(textSize))), then drag out any area.")
                        } else {
                            Text("Click the Shot icon in the menu bar, then Screenshot, and drag out any area.")
                        }
                    }
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                }
            } picture: {
                TryItPicture(keys: area?.keycaps, captured: false)
            } trailing: {
                Button("Skip") { WelcomeWindow.close() }
                    .buttonStyle(ThemeButtonStyle(.plain, large: true))
                    .fixedSize()
            }
        }
    }
}

/// A numbered row in a step's grouped panel.
private struct Instruction: View {
    let number: Int
    let text: LocalizedStringResource

    var body: some View {
        HStack(spacing: 12) {
            Text(number, format: .number)
                .font(.scaled(11, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 20, height: 20)
                .background(Theme.fieldFill, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }
}

/// A row of Try it's tips, its icon in ink.
private struct Tip: View {
    let symbol: String
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.scaled(13, weight: .medium))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
    }
}

// MARK: Step indicator

/// The steps, centred in the title bar: a tick for each one done, the step showing numbered on the accent, and the rest
/// numbered in outline, joined by short lines.
private struct StepIndicator: View {
    let items: [OnboardingIndicatorItem]

    private var summary: String {
        guard let index = items.firstIndex(where: { $0.state == .current }) ?? items.indices.last else {
            return ""
        }
        return String(localized: "Step \(index + 1) of \(items.count): \(items[index].step.name)")
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(Theme.faint(0.2)).frame(width: 24, height: 1.5)
                }
                StepIndicatorItem(number: index + 1, item: item)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
    }
}

private struct StepIndicatorItem: View {
    let number: Int
    let item: OnboardingIndicatorItem

    var body: some View {
        HStack(spacing: 6) {
            mark.frame(width: 18, height: 18)
            Text(item.step.name)
                .font(.scaled(12, weight: item.state == .current ? .semibold : .regular))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var labelColor: AnyShapeStyle {
        switch item.state {
        case .current: AnyShapeStyle(Theme.ink)
        case .done: AnyShapeStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
        case .upcoming: AnyShapeStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch item.state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Theme.window)
                .frame(width: 18, height: 18)
                .background(Theme.ink, in: Circle())
        case .current:
            Text(number, format: .number)
                .font(.system(size: 10.5, weight: .heavy))
                .foregroundStyle(Color(hex: 0x16161A))
                .frame(width: 18, height: 18)
                .background(Theme.accent, in: Circle())
                .inkBorder(Circle(), width: 1.5)
        case .upcoming:
            Text(number, format: .number)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .frame(width: 18, height: 18)
                .inkBorder(Circle(), width: 1.5, color: Theme.ink.opacity(0.25))
        }
    }
}

extension OnboardingStep {
    /// The step's name in the title bar.
    fileprivate var name: String {
        switch self {
        case .permission: String(localized: "Permission")
        case .accessibility: String(localized: "Browser pages")
        case .setup: String(localized: "Shortcuts")
        case .tryIt: String(localized: "Try it")
        }
    }
}

// MARK: Pictures

/// A big key, white with an ink outline and a hard drop, as the board draws the shortcut.
private struct BigKeycap: View {
    let label: String
    @Environment(\.displayScale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
        Text(label)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minWidth: 64, minHeight: 64)
            .background(Theme.group, in: shape)
            .inkBorder(shape, width: 1.5)
            .background {
                shape.fill(Theme.line).offset(y: Theme.inkOffset(4, scale: scale))
            }
            .padding(.bottom, 4)
    }
}

private struct BigKeycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                BigKeycap(label: key)
            }
        }
    }
}

/// An icon on a quiet tile, then what it means.
private struct PictureLine: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular))
            Text(text)
                .font(.scaled(13))
                .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 260, alignment: .leading)
    }
}

/// Setup's picture: the screenshot keys, then what each shortcut does. It follows the first switch, so it shows the keys
/// Shot will use.
private struct ShortcutPicture: View {
    let usesSystemKeys: Bool

    private func combo(_ action: ShotAction) -> KeyCombo? {
        action.defaultCombo(replacingSystemScreenshots: usesSystemKeys)
    }

    private var screenshotLine: String {
        let prefs = Preferences()
        return switch (prefs.copyAfterCapture, prefs.saveAfterCapture) {
        case (true, true): String(localized: "Screenshot, copied and saved")
        case (true, false): String(localized: "Screenshot, copied")
        case (false, true): String(localized: "Screenshot, saved")
        case (false, false): String(localized: "Screenshot of any area")
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            if let screenshot = combo(.screenshot) {
                BigKeycaps(keys: screenshot.keycaps)
            }
            VStack(alignment: .leading, spacing: 12) {
                PictureLine(symbol: "viewfinder", text: screenshotLine)
                if let record = combo(.record) {
                    PictureLine(symbol: "record.circle", text: String(localized: "\(record.displayString) records the screen"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The permission steps' picture: the list in System Settings with Shot's switch on, under a row of another app.
private struct PermissionPicture: View {
    let list: LocalizedStringResource
    let isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(list)
                .font(Theme.small)
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .padding(.leading, 12)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .circular).fill(Theme.fieldFill).frame(width: 28, height: 28)
                    Capsule().fill(Theme.fieldFill).frame(width: 84, height: 8)
                    Spacer()
                    PictureSwitch(isOn: false)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                Theme.separator.frame(height: 1)
                HStack(spacing: 10) {
                    AppIconView(size: 28)
                    Text(verbatim: "Shot").font(Theme.label).foregroundStyle(Theme.ink)
                    Spacer()
                    PictureSwitch(isOn: true)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
            .depth(.group, fill: Theme.group, radius: Theme.Radius.group)
            if isOn {
                Label("Shot is on", systemImage: "checkmark")
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                    .padding(.leading, 12)
            }
        }
        .frame(width: 260)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A drawn switch, which nothing can press: `ThemeToggleStyle`'s look without the control.
private struct PictureSwitch: View {
    let isOn: Bool

    var body: some View {
        if isOn {
            ZStack(alignment: .trailing) {
                Capsule().fill(Theme.accent)
                Circle().fill(.white)
                    .inkBorder(Circle(), width: 1.5)
                    .frame(width: 17, height: 17)
                    .padding(2.5)
            }
            .frame(width: 38, height: 22)
            .inkBorder(Capsule(), width: 1.5)
        } else {
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.quietTrack)
                Circle().fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
        }
    }
}

/// Try it's picture: the screenshot keys over an area being picked, which fills in with a tick once the capture is done.
private struct TryItPicture: View {
    let keys: [String]?
    let captured: Bool

    var body: some View {
        VStack(spacing: 26) {
            if let keys {
                BigKeycaps(keys: keys)
            }
            let shape = RoundedRectangle(cornerRadius: 4, style: .circular)
            ZStack {
                if captured {
                    shape.fill(Theme.group)
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(width: 200, height: 112)
            .inkBorder(shape, width: 1.5, color: Theme.ink.opacity(captured ? 0.14 : 0.6), dash: captured ? [] : [5, 4])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
