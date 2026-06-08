import SwiftUI

/// The "Specs" library — modal sheet listing every locally-saved
/// SpecDraft, newest first. Tap a row to reopen the composer with that
/// draft pre-populated; swipe to delete.
///
/// Sent specs (kind="spec") will additionally show outcome status once
/// SWE backend wire ships the `kind="spec_outcome"` reply path
/// (v2.1 #6). For v2.0 this is local-drafts-only.
struct SpecLibraryView: View {
    let store: DraftStore
    let dispatcher: SpecDispatcher

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [SpecDraft] = []
    @State private var loadError: String?
    @State private var editing: SpecDraft? = nil
    @State private var showingNew: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                ConversationBackdrop().ignoresSafeArea()
                content
            }
            .navigationTitle("Specs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textDim)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.outbound)
                    }
                }
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $editing) { draft in
            SpecComposerView(existing: draft, dispatch: dispatcher, store: store) { _ in
                reload()
            }
        }
        .sheet(isPresented: $showingNew) {
            SpecComposerView(dispatch: dispatcher, store: store) { _ in
                reload()
            }
        }
        .onAppear { reload() }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            errorState(loadError)
        } else if drafts.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(drafts) { draft in
                    row(draft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func row(_ draft: SpecDraft) -> some View {
        Button {
            editing = draft
        } label: {
            HStack(alignment: .top, spacing: 12) {
                targetChip(draft.target)
                VStack(alignment: .leading, spacing: 6) {
                    Text(previewBody(draft.body))
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(relativeTime(draft.updatedAt))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textGhost)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.bubbleInnerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.bubbleInnerRadius, style: .continuous)
                    .stroke(Theme.stroke.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                delete(draft)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func targetChip(_ target: SpecTarget) -> some View {
        let (label, accent): (String, Color) = {
            switch target {
            case .pm:   return ("PM", Theme.macAccent)
            case .swe:  return ("SWE", Theme.pcAccent)
            case .both: return ("Both", Theme.outbound)
            }
        }()
        return Text(label)
            .font(Theme.body(11, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(accent.opacity(0.18))
            )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.textGhost)
            Text("no drafts yet")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textDim)
            Text("tap + to compose a spec")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textGhost)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.outbound)
            Text(msg)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") { reload() }
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.outbound)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: -

    private func reload() {
        do {
            drafts = try store.listAll()
            loadError = nil
        } catch {
            drafts = []
            loadError = "Couldn't load drafts: \(error.localizedDescription)"
        }
    }

    private func delete(_ draft: SpecDraft) {
        try? store.delete(id: draft.id)
        reload()
    }

    private func previewBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(empty draft)" : trimmed
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
