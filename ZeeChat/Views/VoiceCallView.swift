import SwiftUI
import AVFoundation

/// Full-screen voice-call modal — continuous mic capture + transcript
/// preview + tap-to-end. Designed for hands-free spec dictation.
///
/// State machine:
///   .requestingPermission → on grant: .listening
///                         → on deny:  .denied (Settings link)
///   .listening    — mic open, transcript updating live
///   .sending      — user taps "send turn"; payload routed via dispatcher
///   .speaking     — incoming reply is being TTS'd (interrupt by tapping)
///   .ended        — dismiss
///
/// Reply integration: v2.0 ships dispatch-via-chat-thread (the user's
/// spoken turn lands as a normal `[SPEC]` message; the contact's reply
/// shows up in the chat thread). Full audio back-and-forth (auto-listen
/// after TTS finish, VAD-based turn-taking) lands in v2.5 ambient mode.
struct VoiceCallView: View {
    let target: ContactRole
    let chatStore: ChatStore

    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = VoiceCallSession()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ConversationBackdrop().ignoresSafeArea()
            VStack(spacing: 28) {
                header
                Spacer()
                pulseRing
                Spacer()
                transcriptCard
                actionRow
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .task {
            await session.start()
        }
        .onDisappear {
            session.cleanup()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("voice call")
                .font(Theme.body(11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Theme.textGhost)
                .textCase(.uppercase)
            Text(handle)
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
                Text(stateLabel)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private var handle: String {
        switch target {
        case .pm:  return "mac-claude"
        case .swe: return "pc-claude"
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .listening:           return Theme.accent(for: target)
        case .sending, .speaking:  return Theme.outbound
        case .requestingPermission: return Theme.textGhost
        case .denied, .ended:      return Theme.outbound
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .requestingPermission: return "requesting mic + speech…"
        case .listening:            return "listening — speak naturally"
        case .sending:              return "sending turn…"
        case .speaking:             return "reply playing — tap to interrupt"
        case .denied:               return "permission denied — enable in Settings"
        case .ended:                return "ended"
        }
    }

    // MARK: - Pulse ring (visual feedback)

    private var pulseRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent(for: target).opacity(0.25), lineWidth: 1)
                .frame(width: 220, height: 220)
                .scaleEffect(session.isActive ? 1.05 : 1.0)
                .opacity(session.isActive ? 0.0 : 0.6)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false),
                           value: session.isActive)
            Circle()
                .stroke(Theme.accent(for: target).opacity(0.4), lineWidth: 1.5)
                .frame(width: 170, height: 170)
            Circle()
                .fill(Theme.surface)
                .frame(width: 130, height: 130)
                .overlay(
                    Circle().stroke(Theme.stroke.opacity(0.6), lineWidth: 0.5)
                )
            Image(systemName: session.state == .speaking ? "speaker.wave.2.fill" : "mic.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Transcript card

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("transcript")
                .font(Theme.body(10, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(Theme.textGhost)
                .textCase(.uppercase)
            ScrollView {
                Text(session.transcript.isEmpty ? "…" : session.transcript)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.bubbleInnerRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.bubbleInnerRadius, style: .continuous)
                .stroke(Theme.stroke.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await session.sendCurrentTurn(via: chatStore, to: target)
                }
            } label: {
                Text("send turn")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(canSend ? .black : Theme.textGhost)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        Capsule().fill(canSend ? Theme.outbound : Theme.surface)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)

            Button {
                session.cleanup()
                dismiss()
            } label: {
                Text("end")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        Capsule().fill(Theme.surfaceHi)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var canSend: Bool {
        session.state == .listening &&
            !session.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Session driver

/// Owns the live recognizer + synth state for the duration of one
/// voice-call modal. Kept out of the View so the lifecycle is explicit
/// (start in .task, cleanup in .onDisappear) and the state machine is
/// inspectable.
@MainActor
final class VoiceCallSession: ObservableObject {
    enum State: Equatable {
        case requestingPermission
        case listening
        case sending
        case speaking
        case denied
        case ended
    }

    @Published private(set) var state: State = .requestingPermission
    @Published private(set) var transcript: String = ""

    var isActive: Bool {
        state == .listening || state == .speaking
    }

    private let recognizer = VoiceRecognizer()
    private let synth = SpeechSynthesizer()

    func start() async {
        let status = await recognizer.requestAuthorization()
        guard status == .authorized else {
            state = .denied
            return
        }
        do {
            try recognizer.startRecognition { [weak self] text, _ in
                Task { @MainActor in
                    self?.transcript = text
                }
            }
            state = .listening
        } catch {
            state = .denied
        }
    }

    func sendCurrentTurn(via chatStore: ChatStore, to role: ContactRole) async {
        let payload = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }
        state = .sending
        recognizer.stop()
        let body = "[VOICE] " + payload
        await chatStore.send(body: body, to: role)
        // Local UX: short ack so user knows the turn flushed; tap to
        // continue listening for next turn.
        synth.speak("Turn sent. Speak again when ready.") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.transcript = ""
                do {
                    try self.recognizer.startRecognition { [weak self] text, _ in
                        Task { @MainActor in
                            self?.transcript = text
                        }
                    }
                    self.state = .listening
                } catch {
                    self.state = .denied
                }
            }
        }
        state = .speaking
    }

    func cleanup() {
        recognizer.stop()
        synth.stop()
        state = .ended
    }
}
