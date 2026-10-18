import Foundation
import os
import ShotCoreApple

private let log = Logger.shot("text-index")

/// Reads the text in the save folder's screenshots so search can find them by it, in the background, after captures and
/// never in their way. The reading runs in `shot-cli index-text`, a process of its own at background priority, so
/// Vision's memory leaves with it rather than staying in the app. It starts a few seconds after the folder last changed,
/// stops while a recording runs, and waits out Low Power Mode. The gallery and `list_captures` read what it saves.
@MainActor
final class TextIndexer {
    static let shared = TextIndexer()

    /// This app's index, so ShotDev's stays apart from the release's.
    nonisolated static let store = TextIndexStore(bundleID: Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot.dev")
    /// How long the folder has to be still before a capture's text is read, so it never competes with copy and save.
    private static let settle = Duration.seconds(3)

    /// Set by the gallery while it's open: the folded text of each screenshot read so far, by URL, each time more is
    /// read. Nothing is loaded while it's `nil`, so the app holds no text while the gallery is closed.
    var onTexts: (([URL: String]) -> Void)? {
        didSet {
            if onTexts != nil {
                loadTexts()
            } else {
                loadTask?.cancel()
            }
        }
    }
    /// Set while a recording runs: reading stops until it ends.
    var isRecording = false {
        didSet {
            guard isRecording != oldValue else {
                return
            }
            if isRecording {
                debounce?.cancel()
                process?.terminate()
            } else {
                schedule()
            }
        }
    }

    private var folder: URL?
    private var watcher: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var process: Process?
    /// The folder changed while a run was reading it, so another run follows.
    private var rerun = false
    private var powerObserver: NSObjectProtocol?

    /// Follows the save folder: called at launch, whenever settings change and when the gallery opens. It does nothing
    /// unless the folder moved, or it couldn't be watched because it didn't exist yet.
    func update() {
        let saveFolder = Preferences().saveFolder
        guard saveFolder != folder || watcher == nil else {
            return
        }
        folder = saveFolder
        watch(saveFolder)
        if powerObserver == nil {
            powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TextIndexer.shared.schedule() }
            }
        }
        if onTexts != nil {
            loadTexts()
        }
        schedule(after: .seconds(10))
    }

    func stop() {
        debounce?.cancel()
        process?.terminate()
    }

    /// Reads what's new once the folder has been still for `delay`.
    func schedule(after delay: Duration = settle) {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: delay)
            if !Task.isCancelled {
                run()
            }
        }
    }

    private func run() {
        guard process == nil else {
            rerun = true
            return
        }
        guard let folder, !isRecording, !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            return
        }
        guard let cli = Bundle.main.url(forAuxiliaryExecutable: "shot-cli") else {
            log.error("No shot-cli in the app bundle, so screenshots' text isn't read")
            return
        }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["index-text", folder.path]
        process.qualityOfService = .background
        let output = Pipe()
        process.standardOutput = output
        // It writes a line each time it saves.
        output.fileHandleForReading.readabilityHandler = { handle in
            guard !handle.availableData.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in TextIndexer.shared.loadTexts() }
        }
        process.terminationHandler = { process in
            let status = process.terminationStatus, reason = process.terminationReason
            Task { @MainActor in TextIndexer.shared.finished(status: status, reason: reason) }
        }
        do {
            try process.run()
            self.process = process
            rerun = false
        } catch {
            log.error("Couldn't start reading screenshots' text: \(error.localizedDescription)")
        }
    }

    private func finished(status: Int32, reason: Process.TerminationReason) {
        process = nil
        if reason == .exit, status != 0 {
            log.error("Reading screenshots' text stopped with status \(status)")
        }
        if rerun {
            rerun = false
            schedule()
        }
    }

    private func watch(_ folder: URL) {
        watcher?.cancel()
        watcher = nil
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { TextIndexer.shared.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// The folder changed: a run reading it now goes again after, and otherwise one starts once it settles.
    private func changed() {
        if process != nil {
            rerun = true
        } else {
            schedule()
        }
    }

    /// Hands the gallery the text read so far for the folder's screenshots as they are now, folded for search. Reads the
    /// index off the main actor.
    private func loadTexts() {
        guard let folder, onTexts != nil else {
            return
        }
        loadTask?.cancel()
        loadTask = Task {
            let texts = await Task.detached(priority: .utility) {
                let items = Gallery.items(in: folder).filter { $0.kind == .image }
                let folded = Self.store.load().folded(items.map(\.textFile))
                var texts: [URL: String] = [:]
                for item in items {
                    texts[item.url] = folded[item.url.path]
                }
                return texts
            }.value
            if !Task.isCancelled {
                onTexts?(texts)
            }
        }
    }
}
