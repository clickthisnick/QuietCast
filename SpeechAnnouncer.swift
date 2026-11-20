import AVFoundation
import Observation
import os

/// Handles spoken announcements via AVSpeechSynthesizer.
@MainActor
@Observable
final class SpeechAnnouncer {
    static let shared = SpeechAnnouncer()

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechAnnouncerDelegate()
    private let logger = Logger(subsystem: "com.quietcast", category: "SpeechAnnouncer")

    /// Whether speech is currently active.
    private(set) var isSpeaking = false
    /// Identifier of whatever is being spoken (e.g. episode GUID).
    private(set) var speakingIdentifier: String?

    private init() {
        synthesizer.delegate = delegate
    }

    /// Speak a text announcement, then call completion when done.
    func speak(_ text: String, identifier: String? = nil, completion: (() -> Void)? = nil) {
        // Cancel any in-flight announcement's callback instead of firing it,
        // so the podcast doesn't resume while the new speech is playing.
        delegate.onFinish = nil
        synthesizer.stopSpeaking(at: .immediate)

        isSpeaking = true
        speakingIdentifier = identifier
        delegate.onFinish = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = min(0.8, AppSettings.maxVolume)
        if let voice = Self.bestAvailableVoice() {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    /// Immediately stop any current speech without firing a completion callback.
    func stop() {
        delegate.onFinish = nil
        synthesizer.stopSpeaking(at: .immediate)
        markSpeechFinished()
    }

    /// Called by the delegate when speech finishes naturally.
    func markSpeechFinished() {
        isSpeaking = false
        speakingIdentifier = nil
    }

    /// Find the best quality voice available for the user's language.
    private static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return voices.first
    }
}

/// Delegate that fires a callback when speech finishes.
private class SpeechAnnouncerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let callback = onFinish
        onFinish = nil
        Task { @MainActor in
            SpeechAnnouncer.shared.markSpeechFinished()
        }
        callback?()
    }
}
