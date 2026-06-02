import SwiftUI

struct ChatView: View {
    let contact: ContactRole
    @EnvironmentObject var chatStore: ChatStore
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let err = chatStore.lastError {
                errorBanner(err)
            }
            messagesList
            Divider()
            composer
        }
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await chatStore.refreshOnce() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            Task { await chatStore.refreshOnce() }
        }
    }

    private var messages: [DispatchMessage] {
        chatStore.threads[contact] ?? []
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty {
                        emptyState
                            .padding(.top, 80)
                    } else {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                                .padding(.horizontal, 12)
                        }
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No messages yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Say hi to \(contact.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message \(contact.displayName)…",
                      text: $draft,
                      axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .submitLabel(.send)
            Button {
                sendDraft()
            } label: {
                Image(systemName: "paperplane.fill")
                    .padding(8)
                    .background(canSend ? Color.accentColor : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        Task { await chatStore.send(body: text, to: contact) }
    }
}

private struct MessageBubble: View {
    let message: DispatchMessage

    var isFromMe: Bool { message.from_role == "ceo" }

    var body: some View {
        HStack {
            if isFromMe { Spacer(minLength: 40) }
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(isFromMe ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(isFromMe ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let ts = ISO8601.parse(message.created_at) {
                    Text(Self.timeFormatter.string(from: ts))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            if !isFromMe { Spacer(minLength: 40) }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}
