import Foundation
import Speech

/// On-device transcription via Apple's Speech framework.
///
/// Requires `NSSpeechRecognitionUsageDescription` in the embedded Info.plist (see
/// `Package.swift` linker settings) or the Speech API traps at runtime. Forces
/// on-device recognition; never falls back to network silently.
struct AppleSpeechTranscriber: AudioTranscriber {

    enum TranscribeError: LocalizedError {
        case notAuthorized
        case unavailable
        case onDeviceUnsupported

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition permission was denied. Grant it in System Settings → Privacy & Security → Speech Recognition."
            case .unavailable:
                return "Speech recognizer is unavailable for this locale."
            case .onDeviceUnsupported:
                return "On-device speech recognition is not supported for this locale; refusing to transcribe over the network."
            }
        }
    }

    let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }

    func transcribe(audioFileURL: URL) async throws -> String {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscribeError.notAuthorized }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscribeError.unavailable
        }
        guard recognizer.supportsOnDeviceRecognition else { throw TranscribeError.onDeviceUnsupported }

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    once.run { cont.resume(throwing: error) }
                    return
                }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    once.run { cont.resume(returning: text) }
                }
            }
        }
    }
}

/// Guarantees a continuation is resumed exactly once across concurrent callbacks.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ block: () -> Void) {
        lock.lock()
        let shouldRun = !done
        done = true
        lock.unlock()
        if shouldRun { block() }
    }
}
