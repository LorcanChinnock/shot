import AVFoundation
import Foundation
import Speech

/// Hears what's said in a recording with the Speech framework's on-device transcriber: nothing leaves the Mac, and it
/// needs no permission, since it reads a file rather than the microphone. It needs macOS 26.
public enum SpeechRecognizer {
    /// The words said in the audio of the media file at `url`, each with its time in seconds, in the language of the
    /// Mac's locale. `nil` when this Mac can't transcribe: an older macOS, or a language with no on-device model.
    public static func words(in url: URL) async throws -> [Narration.Word]? {
        guard #available(macOS 26, *) else {
            return nil
        }
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            return nil
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        guard await AssetInventory.status(forModules: [transcriber]) != .unsupported else {
            return nil
        }
        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Results stream while the file is read, so collect them alongside.
        async let heard = collect(transcriber)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return try await heard
    }

    @available(macOS 26, *)
    private static func collect(_ transcriber: SpeechTranscriber) async throws -> [Narration.Word] {
        var words: [Narration.Word] = []
        for try await result in transcriber.results {
            for run in result.text.runs {
                guard let range = run.audioTimeRange else {
                    continue
                }
                words.append(Narration.Word(text: String(result.text[run.range].characters), start: range.start.seconds, end: range.end.seconds))
            }
        }
        return words
    }
}
