import Foundation
import Speech
import AVFoundation
import os

/// On-device speech-to-text wrapper around `SFSpeechRecognizer`.
///
/// Used by:
///   - Spec composer mic button (P2, dictation): short bursts, push-
///     to-talk
///   - Voice-call mode (P3): continuous recognition with VAD silence
///     flush
///
/// Privacy: on-device when available (iOS 17+ default for the user's
/// system language). No cloud round-trip.
///
/// Permission flow: `requestAuthorization()` must be called before any
/// `startRecognition()`; first call surfaces the iOS permission
/// prompt. After deny, the user must enable in Settings (we can't
/// re-prompt). `currentAuthorizationStatus` lets the UI route to
/// Settings instead of an empty-mic surprise.
@MainActor
final class VoiceRecognizer: NSObject {
    enum RecognizerError: Error, Equatable {
        case unavailable                  // device or language unsupported
        case permissionDenied             // user denied mic OR speech
        case alreadyRunning               // start called while a task is live
        case audioEngineStartFailed       // AVAudioEngine failed to start
    }

    enum AuthStatus: Equatable {
        case notDetermined
        case denied
        case restricted
        case authorized
    }

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let log = Logger(subsystem: "com.rishizamvar.zeechat", category: "voice.recognizer")

    /// Init with the device's current locale. Override for tests or
    /// multi-language support later.
    init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    /// True if a recognizer exists for the configured locale AND the
    /// device + language support recognition. False on iOS sim with
    /// some locales (test-aware).
    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    /// Current iOS speech-recognition permission status, unified
    /// across SFSpeech + microphone (we need BOTH).
    var currentAuthorizationStatus: AuthStatus {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission
        switch (speech, mic) {
        case (.authorized, .granted):       return .authorized
        case (.notDetermined, _),
             (_, .undetermined):            return .notDetermined
        case (.denied, _), (_, .denied):    return .denied
        case (.restricted, _):              return .restricted
        @unknown default:                   return .denied
        }
    }

    /// One-shot permission request for BOTH speech recognition and
    /// microphone. Returns the resulting unified status.
    func requestAuthorization() async -> AuthStatus {
        // Speech first.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                cont.resume()
            }
        }
        // Mic second.
        _ = await AVAudioApplication.requestRecordPermission()
        return currentAuthorizationStatus
    }

    /// Start a recognition task. Yields partial + final transcripts
    /// via the `onText` callback. Caller must call `stop()` when the
    /// user is done (or to interrupt for voice-call mode).
    ///
    /// `onText(transcript, isFinal)` fires whenever new speech is
    /// recognized. `isFinal=true` indicates a sentence boundary or
    /// stop-detected segment; the recognizer may continue producing
    /// new finals after that until stop() is called.
    func startRecognition(
        onText: @escaping (_ transcript: String, _ isFinal: Bool) -> Void
    ) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw RecognizerError.unavailable
        }
        guard currentAuthorizationStatus == .authorized else {
            throw RecognizerError.permissionDenied
        }
        guard task == nil else {
            throw RecognizerError.alreadyRunning
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            log.error("audio engine start failed: \(error.localizedDescription, privacy: .public)")
            cleanup()
            throw RecognizerError.audioEngineStartFailed
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                onText(result.bestTranscription.formattedString, result.isFinal)
            }
            if error != nil || (result?.isFinal ?? false) {
                self?.cleanup()
            }
        }
    }

    /// Stop the recognition task + tear down the audio engine. Idempotent.
    func stop() {
        cleanup()
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
