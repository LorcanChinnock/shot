import AppKit
import Observation
import ShotCore
import SwiftUI

/// What the update window shows, which `UpdateUserDriver` moves along as Sparkle reports each step.
@MainActor
@Observable
final class UpdatePromptModel {
    enum Phase: Equatable {
        /// A check you asked for is running.
        case checking
        /// A new version is on offer: Skip, Later and Install and Relaunch.
        case offer
        /// Downloading, with the bar filling as the bytes arrive.
        case downloading
        /// Unpacking and checking the download, from 0 to 1.
        case preparing(Double)
        /// Unpacked and waiting for Install and Relaunch.
        case ready
        /// Shot is quitting so the update can go in, and relaunches after.
        case installing
    }

    struct Actions {
        var install: @MainActor () -> Void = {}
        var later: @MainActor () -> Void = {}
        var skip: @MainActor () -> Void = {}
        var cancel: @MainActor () -> Void = {}
        var relaunch: @MainActor () -> Void = {}
        var setInstallsAutomatically: @MainActor (Bool) -> Void = { _ in }
    }

    var phase: Phase = .checking
    var offer: UpdateOffer?
    var download = UpdateDownloadProgress()
    var buttons: UpdatePromptButtons?
    /// Sparkle's "Automatically download and install updates in the future".
    var installsAutomatically = false {
        didSet {
            if installsAutomatically != oldValue {
                actions.setInstallsAutomatically(installsAutomatically)
            }
        }
    }
    /// The download can be cancelled until Sparkle starts unpacking it.
    var canCancel = true
    var actions = Actions()

    var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var title: String {
        if offer == nil {
            return String(localized: "Checking for a new Shot")
        }
        if offer?.isCritical == true {
            return String(localized: "An important update to Shot is ready")
        }
        return String(localized: "A new Shot is ready")
    }

    var subtitle: String {
        guard let offer else {
            return String(localized: "You have \(installedVersion)")
        }
        let versions = offer.versions
        return String(localized: "\(versions.new) · you have \(versions.installed)")
    }
}

/// Shot's own update window (Capture › Permission card… › Update available), in place of Sparkle's. One card carries
/// the whole update: the check you asked for, the offer with what's new, the download, and the relaunch. Errors, "up to
/// date" and Sparkle's first-run question stay Sparkle's own alerts.
final class UpdatePromptWindow: FloatingPanelWindow {
    let model: UpdatePromptModel
    private var shownOnce = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(model: UpdatePromptModel) {
        self.model = model
        let size = NSSize(width: UpdatePromptView.width(Preferences().textSize), height: 200)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless])
        // A normal level, like Sparkle's window: an update offered while you work can sit behind other windows, and
        // the menu bar menu brings it back.
        level = .normal
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        title = String(localized: "Software Update")
        setAccessibilitySubrole(.dialog)
        contentView = NSView(hosting: UpdatePromptView(model: model) { [weak self] size in
            self?.fit(size)
        })
        contentView?.layoutSubtreeIfNeeded()
    }

    /// Esc does what closing Sparkle's window did: Later for an offer, Cancel while checking or downloading. It can't
    /// close the window while the update is being unpacked or installed, as Sparkle's couldn't.
    override func cancelOperation(_ sender: Any?) {
        switch model.phase {
        case .offer:
            model.actions.later()
        case .checking, .downloading:
            if model.canCancel {
                model.actions.cancel()
            }
        case .preparing, .ready, .installing:
            NSSound.beep()
        }
    }

    /// Brings the window forward and makes it key. The first time, it's centred on the screen with the pointer and
    /// rises a few points as it fades in, or only fades with Reduce Motion.
    func present(activating: Bool) {
        if activating {
            NSApp.activate()
        }
        guard !shownOnce || !isVisible else {
            makeKeyAndOrderFront(nil)
            return
        }
        let firstTime = !shownOnce
        shownOnce = true
        if firstTime {
            // Let the content take its height first, so the frame below has it.
            contentView?.layoutSubtreeIfNeeded()
            let frame = centred(frame.size)
            let reduced = Motion.reduced
            alphaValue = 0
            setFrame(reduced ? frame : frame.offsetBy(dx: 0, dy: -8), display: true)
            makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduced ? Moment.reducedFade : Moment.panelArrive.duration
                context.timingFunction = reduced ? CAMediaTimingFunction(name: .easeOut) : Motion.arriveCurve
                animator().alphaValue = 1
                // Only the origin moves, so a height the content asks for meanwhile isn't undone.
                if !reduced {
                    animator().setFrameOrigin(frame.origin)
                }
            }
        } else {
            makeKeyAndOrderFront(nil)
        }
        announce()
    }

    /// Puts the window behind the others, for an update a scheduled check found while you were busy in Shot.
    func presentBehind() {
        if !shownOnce {
            shownOnce = true
            setFrame(centred(frame.size), display: true)
        }
        orderBack(nil)
    }

    func announce() {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "\(model.title). \(model.subtitle)", .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    private func centred(_ size: NSSize) -> NSRect {
        let screen = (NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(x: (screen.midX - size.width / 2).rounded(), y: (screen.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// Takes the height the content needs, keeping the top edge where it is, so the buttons swapping for a progress
    /// bar never makes the header jump.
    private func fit(_ size: CGSize) {
        let wanted = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted != frame.size, wanted.width > 0, wanted.height > 0 else {
            return
        }
        let resting = shownOnce ? frame : centred(frame.size)
        setFrame(NSRect(x: (resting.midX - wanted.width / 2).rounded(), y: resting.maxY - wanted.height, width: wanted.width, height: wanted.height), display: true)
    }
}

struct UpdatePromptView: View {
    @Bindable var model: UpdatePromptModel
    let onSize: (CGSize) -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.textSize) private var textSize

    static let padding: CGFloat = 16
    static let icon: CGFloat = 40

    /// 330 pt on the board, wider with Settings › Text size so the text wraps as it does there.
    static func width(_ textSize: TextSize) -> CGFloat {
        (330 * CGFloat(textSize.scale)).rounded()
    }

    private var increased: Bool { contrast == .increased }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .circular)
        VStack(alignment: .leading, spacing: 0) {
            header
            if let highlights = model.offer?.highlights, !highlights.isEmpty {
                Highlights(items: highlights, increased: increased)
            }
            if model.phase == .offer, model.buttons?.showsAutomaticInstall == true {
                Toggle(isOn: $model.installsAutomatically) {
                    Text("Install future updates automatically")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(ThemeCheckboxStyle())
                .help(String(localized: "Shot downloads each new version by itself and installs it when Shot next quits."))
                .padding(.horizontal, Self.padding)
                .padding(.top, 12)
            }
            footer
                .padding(.horizontal, Self.padding)
                .padding(.vertical, 12)
        }
        .frame(width: Self.width(textSize), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.group, in: shape)
        .clipShape(shape)
        .inkBorder(shape, width: increased ? 1 : 0.5, color: edge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(size: Self.icon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.scaled(14.5, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(model.subtitle)
                    .font(.scaled(12))
                    .foregroundStyle(increased ? Theme.ink : Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.top, Self.padding)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking for a new version…")
                    .font(.scaled(12))
                    .foregroundStyle(increased ? Theme.ink : Theme.secondaryText)
                Spacer(minLength: 8)
                cancelButton
            }
        case .offer:
            offerButtons
        case .downloading:
            progressRow(status: downloadStatus, fraction: model.download.fraction)
        case .preparing(let fraction):
            progressRow(status: String(localized: "Getting the update ready…"), fraction: fraction)
        case .ready:
            HStack(spacing: 8) {
                Text("Ready to install")
                    .font(.scaled(12))
                    .foregroundStyle(increased ? Theme.ink : Theme.secondaryText)
                Spacer(minLength: 8)
                Button { model.actions.relaunch() } label: { Text("Install and Relaunch") }
                    .buttonStyle(ThemeButtonStyle(.main))
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
                    .help(String(localized: "Quit Shot, install the new version and open it again"))
            }
        case .installing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Installing. Shot opens again by itself.")
                    .font(.scaled(12))
                    .foregroundStyle(increased ? Theme.ink : Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Skip on the left, then Later and Install and Relaunch. When a long translation or a large text size leaves no
    /// room, Skip moves under the other two.
    private var offerButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                skipButton
                Spacer(minLength: 8)
                laterButton
                installButton
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    laterButton
                    installButton
                }
                skipButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder private var skipButton: some View {
        if model.buttons?.showsSkip == true {
            Button { model.actions.skip() } label: { Text("Skip") }
                .buttonStyle(ThemeButtonStyle(.plain))
                .fixedSize()
                .help(String(localized: "Don’t offer this version again"))
        }
    }

    @ViewBuilder private var laterButton: some View {
        switch model.buttons?.later {
        case .later:
            Button { model.actions.later() } label: { Text("Later") }
                .buttonStyle(ThemeButtonStyle())
                .fixedSize()
                .help(String(localized: "Ask again at the next check"))
        case .installOnQuit:
            Button { model.actions.later() } label: { Text("Install on Quit") }
                .buttonStyle(ThemeButtonStyle())
                .fixedSize()
                .help(String(localized: "Install the new version the next time Shot quits"))
        case .hidden, nil:
            EmptyView()
        }
    }

    @ViewBuilder private var installButton: some View {
        if model.buttons?.install == .learnMore {
            Button { model.actions.install() } label: { Text("Learn More…") }
                .buttonStyle(ThemeButtonStyle(.main))
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .help(String(localized: "Read about this version on the web"))
        } else {
            Button { model.actions.install() } label: { Text("Install and Relaunch") }
                .buttonStyle(ThemeButtonStyle(.main))
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .help(String(localized: "Download the new version, then quit Shot, install it and open it again"))
        }
    }

    private var cancelButton: some View {
        Button { model.actions.cancel() } label: { Text("Cancel") }
            .buttonStyle(ThemeButtonStyle())
            .fixedSize()
            .disabled(!model.canCancel)
    }

    private var downloadStatus: String {
        let sizes = model.download.sizes { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) }
        if let total = sizes.total {
            return String(localized: "Downloading \(sizes.received) of \(total)")
        }
        return String(localized: "Downloading \(sizes.received)")
    }

    private func progressRow(status: String, fraction: Double?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(status)
                    .font(.scaled(12))
                    .monospacedDigit()
                    .foregroundStyle(increased ? Theme.ink : Theme.secondaryText)
                    .lineLimit(1)
                if let fraction {
                    ThemeProgressBar(value: fraction)
                        .accessibilityLabel(status)
                } else {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(status)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cancelButton
        }
    }

    /// The Float edge: black at 20% in light and white at 14% in dark, and 60% ink with Increase Contrast.
    private var edge: Color {
        if increased {
            return Theme.ink.opacity(0.6)
        }
        return colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.2)
    }
}

/// The release's changes as a bulleted list on the window's tinted band, between hairlines. A long list scrolls.
private struct Highlights: View {
    let items: [String]
    let increased: Bool
    @Environment(\.textSize) private var textSize

    var body: some View {
        let list = VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(verbatim: "•")
                        .accessibilityHidden(true)
                    Text(verbatim: item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.scaled(12.5))
        .lineSpacing(3)
        .foregroundStyle(increased ? Theme.ink : Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 20)
        .padding(.trailing, UpdatePromptView.padding)
        .padding(.top, 10)
        .padding(.bottom, 12)

        // A scroll view gives the card no height of its own, which left the window too short, so only a long list
        // scrolls, at a fixed height.
        Group {
            if items.count > 6 {
                ScrollView { list }
                    .frame(height: (180 * CGFloat(textSize.scale)).rounded())
            } else {
                list
            }
        }
        .background { Rectangle().fill(Theme.window) }
        .overlay(alignment: .top) { divider }
        .overlay(alignment: .bottom) { divider }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "What’s new"))
    }

    private var divider: some View {
        Rectangle()
            .fill(increased ? Theme.ink.opacity(0.6) : Theme.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
