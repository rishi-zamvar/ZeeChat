import SwiftUI
import os

/// The spec composer: where CEO drafts a request, picks a target
/// (PM / SWE / both), optionally refines via Claude round-trip, and
/// dispatches as `kind="spec"`. Modal sheet, presented from the chat
/// composer's "Spec" button or the global Specs tab "+ new" button.
///
/// State machine:
///   idle       — composer open, body editable, can save/refine/send
///   refining   — refine_request in flight; body locked grey, spinner
///                pulses; on response: body replaced + back to idle
///   sending    — send dispatch in flight; sheet dismisses on success
///                or back to idle on error with a banner
///
/// Drafts auto-save to local DraftStore on every body edit (debounced).
/// ZeeCloud sync lands when SWE's /api/drafts endpoints ship.
struct SpecComposerView: View {
    /// Pre-populate the composer with an existing draft (e.g. from
    /// the Specs library "Clone" action). nil = brand new spec.
    let existing: SpecDraft?
    /// Called when the user successfully dispatches the spec. Sheet
    /// dismisses; caller appends to the local Specs library.
    let onSent: (SpecDraft) -> Void
    /// Dispatcher seam — injected so previews + tests can run without
    /// a real DispatchClient. Production wires this to
    /// DispatchClient.send(kind:body:target:).
    let dispatch: SpecDispatcher
    /// Local persistence seam — injected for same reason. Default
    /// production store lives at Documents/drafts/.
    let store: DraftStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SpecDraft
    @State private var phase: Phase = .idle
    @State private var error: String?
    /// Debounce timer for auto-save on edits.
    @State private var autosaveTask: Task<Void, Never>?

    enum Phase: Equatable {
        case idle
        case refining
        case sending
    }

    init(
        existing: SpecDraft? = nil,
        dispatch: SpecDispatcher,
        store: DraftStore,
        onSent: @escaping (SpecDraft) -> Void
    ) {
        self.existing = existing
        self.dispatch = dispatch
        self.store = store
        self.onSent = onSent
        let d = existing ?? SpecDraft(
            id: UUID().uuidString,
            target: .both,
            body: "",
            updatedAt: Date()
        )
        self._draft = State(initialValue: d)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ConversationBackdrop().ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    targetChips
                    bodyField
                    Spacer(minLength: 0)
                    if let error {
                        errorBanner(error)
                    }
                    actionRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .dismissKeyboardOnTapOutside()
            .navigationTitle("Spec")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Target chips (PM / SWE / both)

    private var targetChips: some View {
        HStack(spacing: 8) {
            chip(label: "PM", isOn: draft.target == .pm, accent: Theme.macAccent) { draft.target = .pm }
            chip(label: "SWE", isOn: draft.target == .swe, accent: Theme.pcAccent) { draft.target = .swe }
            chip(label: "Both", isOn: draft.target == .both, accent: Theme.outbound) { draft.target = .both }
            Spacer()
        }
    }

    private func chip(label: String, isOn: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(isOn ? Theme.textPrimary : Theme.textDim)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? accent.opacity(0.25) : Theme.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isOn ? accent.opacity(0.55) : Theme.stroke.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(phase != .idle)
    }

    // MARK: - Body text field (multiline)

    private var bodyField: some View {
        TextEditor(text: $draft.body)
            .font(Theme.body(15))
            .foregroundStyle(phase == .refining ? Theme.textDim : Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.bubbleInnerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.bubbleInnerRadius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.5)
            )
            .frame(minHeight: 200, maxHeight: 360)
            .disabled(phase != .idle)
            .onChange(of: draft.body) { _, _ in scheduleAutosave() }
            .overlay(alignment: .center) {
                if phase == .refining {
                    refiningOverlay
                }
            }
    }

    private var refiningOverlay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Theme.textDim)
            Text("refining…")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Theme.bg.opacity(0.85))
        )
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(Theme.body(13))
            .foregroundStyle(Theme.outbound)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.outbound.opacity(0.12))
            )
    }

    // MARK: - Action row (refine + send)

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await refine() }
            } label: {
                Text("Refine")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(Theme.surfaceHi)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canRefine)

            Button {
                Task { await send() }
            } label: {
                Text(sendButtonLabel)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(canSend ? Color.black : Theme.textGhost)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(canSend ? Theme.outbound : Theme.surface)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    private var canRefine: Bool {
        phase == .idle && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        phase == .idle && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonLabel: String {
        switch draft.target {
        case .pm:   return "Send to PM"
        case .swe:  return "Send to SWE"
        case .both: return "Send to both"
        }
    }

    // MARK: - Actions

    /// Refine round-trip via dispatcher. Body locks while in-flight;
    /// on success the body is replaced with the refined version. On
    /// timeout / error a banner surfaces + body stays editable.
    private func refine() async {
        guard canRefine else { return }
        phase = .refining
        error = nil
        do {
            let refined = try await dispatch.refine(body: draft.body, target: draft.target)
            await MainActor.run {
                draft.body = refined
                draft.updatedAt = Date()
                phase = .idle
                scheduleAutosave()
            }
        } catch RefineError.timeout {
            await MainActor.run {
                error = "Refine timed out — the receiving Claude didn't answer in 30s. Try again or just send as-is."
                phase = .idle
            }
        } catch {
            await MainActor.run {
                self.error = "Refine failed: \(error.localizedDescription)"
                phase = .idle
            }
        }
    }

    private func send() async {
        guard canSend else { return }
        phase = .sending
        error = nil
        let snapshot = draft
        do {
            try await dispatch.send(kind: "spec", body: snapshot.body, target: snapshot.target)
            try? store.delete(id: snapshot.id) // sent drafts are no longer drafts
            await MainActor.run {
                onSent(snapshot)
                dismiss()
            }
        } catch {
            await MainActor.run {
                self.error = "Send failed: \(error.localizedDescription). Tap Send again to retry."
                phase = .idle
            }
        }
    }

    /// Debounced autosave — fires 400ms after the last keystroke so we
    /// aren't writing on every character. Cancels any in-flight save
    /// when a new edit lands.
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            var snapshot = draft
            snapshot.updatedAt = Date()
            _ = try? store.save(snapshot)
        }
    }
}

// MARK: - Dispatcher seam

/// Abstracts the wire layer so the composer + its tests don't need a
/// real DispatchClient. Production wires `refine` to RefineCoordinator
/// + the inbox poller; `send` to DispatchClient.send.
protocol SpecDispatcher {
    func refine(body: String, target: SpecTarget) async throws -> String
    func send(kind: String, body: String, target: SpecTarget) async throws
}
