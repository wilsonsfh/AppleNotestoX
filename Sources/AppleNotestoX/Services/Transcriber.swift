import Foundation

/// Pluggable speech-to-text engine. Default impl is `AppleSpeechTranscriber`
/// (on-device Apple Speech); a WhisperKit-backed impl can be swapped in later
/// without touching the orchestration.
protocol AudioTranscriber: Sendable {
    /// Transcribes an audio file (expected ≤ ~1 minute for Apple Speech; callers chunk).
    func transcribe(audioFileURL: URL) async throws -> String
}
