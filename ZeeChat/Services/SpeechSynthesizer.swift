import Foundation
import AVFoundation
import os

/// On-device text-to-speech wrapper around `AVSpeechSynthesizer`.
///
/// Used by voice-call mode (P3): Claude responds with text, iOS speaks
/// it aloud, user can interrupt by tapping a stop button OR by starting
/// to talk (interrupt detection happens at the VoiceCallView level via
/// VAD on the recognizer's incoming buffers).
///
/// Voice selection: prefer enhanced/premium voices when available
/// (`.enhanced` quality); fall back to `.default`. Locale matches the
/// device.
@MainActor
final class SpeechSynthesizer: NSObject {
    private let synth = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "com.rishizamvar.zeechat", category: "voice.synthesizer")

    /// True while a current utterance is mid-speech. Caller (VoiceCallView)
    /// uses this to know whether tap-to-interrupt is meaningful right now.
    var isSpeaking: Bool {
        synth.isSpeaking
    }

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speak `text` aloud in the device locale. If already speaking,
    /// the prior utterance is stopped first (no queue — this is a
    /// conversational synth, not a podcast app).
    ///
    /// `onFinished` fires when the utterance completes naturally OR
    /// is interrupted via `stop()`.
    func speak(_ text: String, onFinished: (() -> Void)? = nil) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        // Activate audio session for playback. Voice-call mode handles
        // the playAndRecord category separately via VoiceRecognizer's
        // startRecognition — here we just ensure playback works.
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            log.error("audio session activation failed: \(error.localizedDescription, privacy: .public)")
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        finishHandlers[utterance] = onFinished
        synth.speak(utterance)
    }

    /// Stop any in-flight utterance immediately. Used by tap-to-interrupt
    /// in voice-call mode. The pending `onFinished` for that utterance
    /// still fires (via delegate didCancel).
    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
    }

    // MARK: -

    /// Per-utterance completion callbacks. Cleared on speak/cancel.
    /// Uses a weak-by-identity dictionary keyed on the utterance.
    private var finishHandlers: [AVSpeechUtterance: (() -> Void)] = [:]

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let langCode = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == langCode }
        // Pick the highest quality available for this locale.
        return voices.max(by: { lhs, rhs in lhs.quality.rawValue < rhs.quality.rawValue })
            ?? AVSpeechSynthesisVoice(language: langCode)
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            finishHandlers.removeValue(forKey: utterance)?()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            finishHandlers.removeValue(forKey: utterance)?()
        }
    }
}
