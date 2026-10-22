import AppKit
import OSLog
import ShotCore
import SwiftUI
@preconcurrency import Translation

/// **Translate Text**: reads the text in a capture and copies it translated, on the Mac, like Copy Text. macOS 26 and
/// later, where Translation runs without its own UI; on macOS 15 a session can only come from a SwiftUI view, so the
/// menu items don't show there.
@MainActor
enum Translator {
    private static let log = Logger.shot("translate")

    static var isAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// The languages to offer, read once in the background, since asking Translation takes a moment.
    private static var supported: [Locale.Language] = []

    /// Starts reading the languages, so the menus have them when they open.
    static func prepare() {
        guard isAvailable, supported.isEmpty else {
            return
        }
        Task { supported = await TextTranslation.languages() }
    }

    /// The language last translated into, or the Mac's language.
    static var target: Locale.Language {
        let saved = UserDefaults.standard.string(forKey: PreferenceKey.translateTarget) ?? ""
        return saved.isEmpty ? Locale.current.language : Locale.Language(identifier: saved)
    }

    /// The menu's languages: the last used first, then the rest by name.
    static var languages: [(language: Locale.Language, title: String)] {
        let first = target
        let rest = supported.filter { !TextTranslation.same($0, first) }
        return ([first] + rest).map { ($0, TextTranslation.name($0)) }
    }

    /// Reads the text in the image file at `url` and copies it in `language`.
    static func translate(imageAt url: URL, to language: Locale.Language) async {
        let read = await Task.detached { try? await TextRecognizer.recognize(fileAt: url) }.value
        guard let text = read ?? nil else {
            Toast.error("Couldn't read \(url.lastPathComponent)")
            return
        }
        await translate(text, to: language)
    }

    static func translate(image: CGImage, to language: Locale.Language) async {
        let sendable = SendableImage(image)
        guard let text = await Task.detached(operation: { try? await TextRecognizer.recognize(sendable.image) }).value else {
            Toast.error("Couldn't read the text")
            return
        }
        await translate(text, to: language)
    }

    private static func translate(_ text: CaptureText, to target: Locale.Language) async {
        UserDefaults.standard.set(target.minimalIdentifier, forKey: PreferenceKey.translateTarget)
        let paragraphs = TextTranslation.paragraphs(text)
        let name = TextTranslation.name(target)
        guard !paragraphs.isEmpty else {
            Toast.show("No text found")
            return
        }
        guard #available(macOS 26, *) else {
            return
        }
        let source = TextTranslation.language(of: paragraphs)
        if let source, TextTranslation.same(source, target) {
            Toast.show("The text is already in \(name)")
            return
        }
        do {
            let readiness: TextTranslation.Readiness? = if let source { await TextTranslation.readiness(from: source, to: target) } else { nil }
            let translated: [String]?
            if let source, readiness == .unsupported {
                Toast.error("Translation can't translate \(TextTranslation.name(source)) into \(name)")
                return
            } else if let source, readiness == .installed {
                Toast.progress("Translating into \(name)…")
                translated = try await TextTranslation.translate(paragraphs, from: source, to: target)
            } else {
                // A language to download, or one Shot couldn't tell: Apple's own prompt asks, and works out the source.
                translated = try await TranslationPrompt.run(paragraphs, from: source, to: target)
            }
            guard let translated else {
                return
            }
            Clipboard.copy(string: TextTranslation.output(translated))
            Toast.show("Copied the text in \(name)")
        } catch {
            log.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            Toast.error("Couldn't translate the text: \(error.localizedDescription)")
        }
    }
}

/// A small window that hosts Translation's SwiftUI task, the only way to show Apple's prompt to download a language.
/// It closes once the translation is done or the prompt is cancelled.
@MainActor
private enum TranslationPrompt {
    /// `nil` when the user cancels the download.
    static func run(_ paragraphs: [String], from source: Locale.Language?, to target: Locale.Language) async throws -> [String]? {
        try await withCheckedThrowingContinuation { continuation in
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 90), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = String(localized: "Translate Text")
            panel.isReleasedWhenClosed = false
            var closing: NSObjectProtocol?
            var finished = false
            // Breaks every reference back to the panel, so it and the translation task go once it's done.
            let finish: @MainActor (Result<[String]?, Error>) -> Void = { result in
                guard !finished else { return }
                finished = true
                if let closing {
                    NotificationCenter.default.removeObserver(closing)
                }
                closing = nil
                panel.close()
                panel.contentView = nil
                continuation.resume(with: result)
            }
            let view = PromptView(paragraphs: paragraphs, configuration: TranslationSession.Configuration(source: source, target: target), finish: finish)
            panel.contentView = NSView(hosting: view)
            closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated { finish(.success(nil)) }
            }
            panel.center()
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private struct PromptView: View {
        let paragraphs: [String]
        let configuration: TranslationSession.Configuration
        let finish: @MainActor (Result<[String]?, Error>) -> Void

        var body: some View {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Getting the languages ready…").font(Brutal.label)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .translationTask(configuration) { session in
                do {
                    finish(.success(try await TextTranslation.prepareAndTranslate(paragraphs, with: session)))
                } catch is CancellationError {
                    finish(.success(nil))
                } catch is TranslationError {
                    // Done without downloading the languages throws "Unable to Translate", which isn't a failure.
                    Toast.show("Translate Text needs both languages downloaded")
                    finish(.success(nil))
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }
}
