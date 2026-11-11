import AppKit
import os
import ShotCore
import Sparkle

private let log = Logger.shot("update")

/// Sparkle's user interface for Shot. `UpdatePromptWindow` draws the check you asked for, the offer, the download and
/// the relaunch, in place of Sparkle's standard windows. Sparkle's own alerts still show its first-run question
/// (whether to check automatically), "up to date", errors and "installed", through a standard driver this one hands
/// those to.
///
/// Every choice means what it meant in Sparkle's window: Skip never offers that version again, Later asks at the next
/// check, closing the window is Later, and a critical update can't be put off. One difference: Install and Relaunch
/// installs as soon as the download is ready, where Sparkle asked a second time, since you already chose to.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    private let standard: SPUStandardUserDriver
    private weak var owner: Updater?
    weak var updater: SPUUpdater?

    private let model = UpdatePromptModel()
    private var window: UpdatePromptWindow?
    private var item: SUAppcastItem?

    private var choiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var cancellation: (() -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var retryTermination: (() -> Void)?
    /// Install and Relaunch was pressed in this session, so the ready step installs without asking again.
    private var choseInstall = false
    private var receivedAttention = false
    private var opportuneTime = ContinuousClock.now
    private var observers: [NSObjectProtocol] = []

    init(owner: Updater, standardDelegate: SPUStandardUserDriverDelegate) {
        self.owner = owner
        standard = SPUStandardUserDriver(hostBundle: .main, delegate: standardDelegate)
        super.init()
        model.actions = UpdatePromptModel.Actions(
            install: { [weak self] in self?.install() },
            later: { [weak self] in self?.choose(.dismiss) },
            skip: { [weak self] in self?.choose(.skip) },
            cancel: { [weak self] in self?.cancel() },
            relaunch: { [weak self] in self?.relaunch() },
            // Sparkle's checkbox changed the setting at once, before any button, and so does this one.
            setInstallsAutomatically: { [weak self] on in self?.updater?.automaticallyDownloadsUpdates = on }
        )
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteAttention() }
        })
        // noteAttention checks that it's the update window that became key.
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteAttention() }
        })
    }

    // MARK: Asking first

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }

    // MARK: Checking

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        model.offer = nil
        model.buttons = nil
        model.canCancel = true
        model.phase = .checking
        promptWindow().present(activating: true)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        item = appcastItem
        choiceReply = reply
        cancellation = nil
        choseInstall = false
        receivedAttention = false
        let offer = Self.offer(appcastItem, state: state)
        model.offer = offer
        model.buttons = UpdatePromptButtons(
            offer: offer,
            automaticallyChecks: updater?.automaticallyChecksForUpdates ?? false,
            allowsAutomaticUpdates: updater?.allowsAutomaticUpdates ?? false
        )
        model.installsAutomatically = updater?.automaticallyDownloadsUpdates ?? false
        model.phase = .offer
        log.notice("Update \(appcastItem.displayVersionString) available")
        owner?.updateShown(version: appcastItem.displayVersionString, userInitiated: state.userInitiated)
        if state.userInitiated {
            promptWindow().present(activating: true)
        } else {
            showScheduled()
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard model.offer?.highlights.isEmpty == true else {
            return
        }
        let encoding = downloadData.textEncodingName
            .map { CFStringConvertIANACharSetNameToEncoding($0 as CFString) }
            .flatMap { $0 == kCFStringEncodingInvalidId ? nil : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding($0)) } ?? .utf8
        guard let notes = String(data: downloadData.data, encoding: encoding) else {
            return
        }
        let format = ReleaseHighlights.format(mimeType: downloadData.mimeType, pathExtension: downloadData.url.pathExtension)
        model.offer?.highlights = ReleaseHighlights.parse(notes, format: format)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        log.error("Release notes didn't download: \(error.localizedDescription, privacy: .public)")
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        closeWindow()
        standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        closeWindow()
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    // MARK: Downloading and installing

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        model.download = UpdateDownloadProgress()
        model.canCancel = true
        model.phase = .downloading
        showIfHidden()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        model.download.expect(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        model.download.receive(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        model.canCancel = false
        model.phase = .preparing(0)
        showIfHidden()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        model.phase = .preparing(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if choseInstall {
            log.notice("Update ready; installing and relaunching as chosen")
            model.phase = .installing
            reply(.install)
            return
        }
        installReply = reply
        model.phase = .ready
        promptWindow().present(activating: false)
        NSApp.requestUserAttention(.informationalRequest)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if applicationTerminated {
            model.phase = .installing
            return
        }
        // Shot didn't quit, because an editor's Cancel or a recording held it up. Sparkle installs when Shot next
        // quits, and Check for Updates offers Install and Relaunch again.
        retryTermination = retryTerminatingApplication
        closeWindow()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        closeWindow()
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func showUpdateInFocus() {
        if let window, window.isVisible {
            window.present(activating: true)
        } else if retryTermination != nil {
            model.phase = .ready
            promptWindow().present(activating: true)
        } else {
            standard.showUpdateInFocus()
        }
    }

    func dismissUpdateInstallation() {
        choiceReply = nil
        cancellation = nil
        installReply = nil
        retryTermination = nil
        choseInstall = false
        receivedAttention = false
        item = nil
        closeWindow()
        standard.dismissUpdateInstallation()
        owner?.updateSessionEnded()
    }

    // MARK: Gentle reminders

    /// Sparkle calls this, when it's there, at launch and after each check it schedules, so an update found within 3
    /// seconds can take the keyboard.
    @objc func resetTimeSinceOpportuneUpdateNotice() {
        opportuneTime = .now
    }

    /// Sparkle warns a background app that has no gentle reminders. Shot has them: the menu's "Update to Shot …" row
    /// and the dot on its menu bar icon.
    @objc func logGentleScheduledUpdateReminderWarningIfNeeded() {}

    /// Shows an update a scheduled check found, as Sparkle's standard driver does for a menu bar app. Near launch it
    /// takes the keyboard. Otherwise it appears without taking the keyboard from another app, and behind Shot's own
    /// windows while you're using one, and the menu bar row stays until you look at it.
    private func showScheduled() {
        let nearLaunch = ContinuousClock.now - opportuneTime <= .seconds(3)
        let window = promptWindow()
        if nearLaunch {
            window.present(activating: true)
        } else if NSApp.isActive, NSApp.keyWindow != nil {
            window.presentBehind()
        } else {
            window.present(activating: false)
        }
    }

    /// The person has seen the offer once its window is key while Shot is active, as Sparkle's standard driver judges it.
    private func noteAttention() {
        guard !receivedAttention, model.phase == .offer, let window, window.isKeyWindow, NSApp.isActive else {
            return
        }
        receivedAttention = true
        owner?.updateGotAttention()
    }

    // MARK: Choices

    private func install() {
        guard let offer = model.offer else {
            return
        }
        if offer.isInformationOnly {
            if let url = item?.infoURL {
                NSWorkspace.shared.open(url)
            }
            choose(.dismiss)
            return
        }
        choseInstall = true
        switch offer.stage {
        case .notDownloaded:
            model.download = UpdateDownloadProgress()
            model.canCancel = false
            model.phase = .downloading
        case .downloaded:
            model.canCancel = false
            model.phase = .preparing(0)
        case .installing:
            model.phase = .installing
        }
        reply(.install)
    }

    private func choose(_ choice: SPUUserUpdateChoice) {
        reply(choice)
        closeWindow()
    }

    private func reply(_ choice: SPUUserUpdateChoice) {
        if !receivedAttention {
            receivedAttention = true
            owner?.updateGotAttention()
        }
        let reply = choiceReply
        choiceReply = nil
        reply?(choice)
    }

    private func cancel() {
        let cancellation = cancellation
        self.cancellation = nil
        cancellation?()
        closeWindow()
    }

    private func relaunch() {
        model.phase = .installing
        if let installReply {
            self.installReply = nil
            installReply(.install)
        } else if let retryTermination {
            retryTermination()
        }
    }

    // MARK: The window

    private func promptWindow() -> UpdatePromptWindow {
        if let window {
            return window
        }
        let window = UpdatePromptWindow(model: model)
        self.window = window
        return window
    }

    private func showIfHidden() {
        if window?.isVisible != true {
            promptWindow().present(activating: false)
        }
    }

    private func closeWindow() {
        window?.orderOut(nil)
        window = nil
    }

    private static func offer(_ item: SUAppcastItem, state: SPUUserUpdateState) -> UpdateOffer {
        let info = Bundle.main.infoDictionary ?? [:]
        let stage: UpdateOffer.Stage = switch state.stage {
        case .downloaded: .downloaded
        case .installing: .installing
        default: .notDownloaded
        }
        var highlights: [String] = []
        if let notes = item.itemDescription {
            let format: ReleaseHighlights.Format = switch item.itemDescriptionFormat {
            case "markdown": .markdown
            case "plain-text": .plainText
            default: .html
            }
            highlights = ReleaseHighlights.parse(notes, format: format)
        }
        return UpdateOffer(
            version: item.displayVersionString,
            build: item.versionString,
            installedVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            installedBuild: info["CFBundleVersion"] as? String ?? "?",
            stage: stage,
            isCritical: item.isCriticalUpdate,
            isMajorUpgrade: item.isMajorUpgrade,
            isInformationOnly: item.isInformationOnlyUpdate,
            highlights: highlights
        )
    }
}
