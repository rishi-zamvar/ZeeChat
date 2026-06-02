import SwiftUI

struct ChatView: View {
    let contact: ContactRole
    @EnvironmentObject var chatStore: ChatStore
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            DotGrid().ignoresSafeArea()
            VStack(spacing: 0) {
                if let err = chatStore.lastError {
                    errorBanner(err)
                }
                messagesList
                composer
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.accent(for: contact))
                        .frame(width: 6, height: 6)
                    Text(handle(for: contact))
                        .font(Theme.mono(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await chatStore.refreshOnce() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
        .onAppear {
            chatStore.visibleContact = contact
            Task {
                await chatStore.refreshOnce()
                chatStore.markRead(role: contact)
            }
        }
        .onDisappear { chatStore.visibleContact = nil }
        .refreshable {
            await chatStore.refreshOnce()
            chatStore.markRead(role: contact)
        }
    }

    private func handle(for role: ContactRole) -> String {
        switch role {
        case .pm:  return "mac-claude@pm"
        case .swe: return "pc-claude@swe"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text("ERR")
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.outbound)
            Text(message)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.outbound)
                .lineLimit(3)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.outbound.opacity(0.12))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.outbound.opacity(0.4)),
                 alignment: .bottom)
    }

    private var messages: [DispatchMessage] {
        chatStore.threads[contact] ?? []
    }

    private var isThinking: Bool {
        chatStore.thinking[contact] ?? false
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if messages.isEmpty && !isThinking {
                        emptyState.padding(.top, 80)
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { idx, msg in
                            MessageBubble(
                                message: msg,
                                contact: contact,
                                isLastOutgoing: isLastOutgoing(at: idx),
                                showsDayBreak: showsDayBreak(at: idx)
                            )
                            .id(msg.id)
                            .padding(.horizontal, 12)
                        }
                        if isThinking {
                            TypingBubble(contact: contact)
                                .padding(.horizontal, 12)
                                .id("typing")
                        }
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                chatStore.markRead(role: contact)
            }
            .onChange(of: isThinking) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func isLastOutgoing(at idx: Int) -> Bool {
        for i in (0..<messages.count).reversed() {
            if messages[i].from_role == "ceo" { return i == idx }
        }
        return false
    }

    /// Show a day-break stamp ("--- TUE JUN 02 ---") when the gap from
    /// the previous message crosses a calendar day boundary.
    private func showsDayBreak(at idx: Int) -> Bool {
        guard idx > 0 else { return true }
        guard let prev = ISO8601.parse(messages[idx - 1].created_at),
              let curr = ISO8601.parse(messages[idx].created_at) else { return false }
        let cal = Calendar(identifier: .gregorian)
        return !cal.isDate(prev, inSameDayAs: curr)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("[ idle ]")
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.textGhost)
            Text("> send a message to \(handle(for: contact))")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textDim)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.stroke.opacity(0.7))
                .frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                Text(">")
                    .font(Theme.mono(15, weight: .bold))
                    .foregroundStyle(Theme.outbound)
                    .padding(.top, 10)
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("type a message…")
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.textGhost)
                            .padding(.vertical, 10)
                    }
                    TextField("", text: $draft, axis: .vertical)
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.outbound)
                        .lineLimit(1...5)
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .padding(.vertical, 10)
                }
                Button(action: sendDraft) {
                    Text("[SEND]")
                        .font(Theme.mono(12, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(canSend ? Theme.bg : Theme.textGhost)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(canSend ? Theme.outbound : Theme.surface)
                }
                .disabled(!canSend)
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.bg)
        }
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

// MARK: - Message bubble (Tailnet Terminal)

private struct MessageBubble: View {
    let message: DispatchMessage
    let contact: ContactRole
    let isLastOutgoing: Bool
    let showsDayBreak: Bool

    var isFromMe: Bool { message.from_role == "ceo" }
    var wasSeen: Bool { (message.read_at?.isEmpty == false) }
    var wasDelivered: Bool { (message.delivered_at?.isEmpty == false) }

    var accent: Color {
        isFromMe ? Theme.outbound : Theme.accent(for: contact)
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsDayBreak, let ts = ISO8601.parse(message.created_at) {
                dayBreak(ts)
            }
            HStack(alignment: .bottom, spacing: 0) {
                if isFromMe { Spacer(minLength: 40) }
                VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                    headerLine
                    bubbleBody
                    if isFromMe && isLastOutgoing {
                        receiptRow
                    }
                }
                if !isFromMe { Spacer(minLength: 40) }
            }
        }
    }

    private func dayBreak(_ ts: Date) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
            Text(Self.dayFmt.string(from: ts).uppercased())
                .font(Theme.mono(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Theme.textGhost)
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
        .padding(.horizontal, 4)
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            if !isFromMe {
                Text("◆ \(handle)")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(accent)
            }
            if let ts = ISO8601.parse(message.created_at) {
                Text(Self.timeFmt.string(from: ts))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textGhost)
            }
            if isFromMe {
                Text("ceo ◆")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 2)
    }

    private var bubbleBody: some View {
        HStack(alignment: .top, spacing: 8) {
            // Prompt glyph — gives each message a CLI prefix on the
            // accent-color side. Reads as "this line of output".
            if !isFromMe {
                Text(">")
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(accent)
            }
            Text(message.body)
                .font(Theme.mono(14))
                .lineSpacing(3)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if isFromMe {
                Text("<")
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.vertical, Theme.bubblePadV)
        .padding(.horizontal, Theme.bubblePadH)
        .background(Theme.surface)
        .clipShape(BubbleShape(isFromMe: isFromMe))
        .overlay(
            BubbleShape(isFromMe: isFromMe)
                .stroke(accent.opacity(0.55), lineWidth: 1)
        )
    }

    private var receiptRow: some View {
        HStack(spacing: 6) {
            if wasSeen {
                StatusPill(label: "SEEN", color: Theme.stateSeen)
            } else if wasDelivered {
                StatusPill(label: "DELIVERED", color: Theme.stateDelivered)
            } else {
                StatusPill(label: "SENT", color: Theme.stateSent)
            }
        }
        .padding(.horizontal, 2)
    }

    private var handle: String {
        switch contact {
        case .pm:  return "mac-claude"
        case .swe: return "pc-claude"
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM dd"
        return f
    }()
}

// MARK: - Typing bubble (Tailnet Terminal)

private struct TypingBubble: View {
    let contact: ContactRole
    @State private var step: Int = 0

    var accent: Color { Theme.accent(for: contact) }
    var handle: String {
        switch contact {
        case .pm:  return "mac-claude"
        case .swe: return "pc-claude"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("◆ \(handle)")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 2)
                HStack(alignment: .center, spacing: 8) {
                    Text(">")
                        .font(Theme.mono(14, weight: .bold))
                        .foregroundStyle(accent)
                    Text(typingText)
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.textDim)
                        .monospaced()
                    BlinkingCaret(color: accent)
                }
                .padding(.vertical, Theme.bubblePadV)
                .padding(.horizontal, Theme.bubblePadH)
                .background(Theme.surface)
                .clipShape(BubbleShape(isFromMe: false))
                .overlay(
                    BubbleShape(isFromMe: false)
                        .stroke(accent.opacity(0.55), lineWidth: 1)
                )
            }
            Spacer(minLength: 40)
        }
        .onAppear {
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await MainActor.run { step = (step + 1) % 4 }
                }
            }
        }
    }

    private var typingText: String {
        switch step {
        case 0:  return "thinking"
        case 1:  return "thinking."
        case 2:  return "thinking.."
        default: return "thinking..."
        }
    }
}
