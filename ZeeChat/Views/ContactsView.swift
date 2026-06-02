import SwiftUI

struct ContactsView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject var chatStore: ChatStore

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            DotGrid().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    ForEach(ContactRole.allCases) { role in
                        NavigationLink(value: role) {
                            ContactRow(role: role)
                        }
                        .buttonStyle(.plain)
                    }
                    footer
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable {
                await chatStore.refreshOnce()
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ZEECHAT")
                    .font(Theme.mono(13, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(Theme.textPrimary)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await chatStore.refreshOnce() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                .accessibilityLabel("Refresh")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("$")
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.outbound)
                Text("tailnet --list-peers")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.textDim)
            }
            Text("2 nodes online ◆ encrypted via wireguard")
                .font(Theme.mono(10))
                .tracking(0.4)
                .foregroundStyle(Theme.textGhost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("// inbox polled every 5s")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textGhost)
            Text("// pull-to-refresh forces sync")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textGhost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }
}

private struct ContactRow: View {
    @EnvironmentObject var chatStore: ChatStore
    let role: ContactRole

    var accent: Color { Theme.accent(for: role) }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                handleLine
                previewLine
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let ts = chatStore.lastMessagePreview(for: role)?.ts {
                    Text(Self.relativeFormatter.localizedString(for: ts, relativeTo: Date()))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textGhost)
                }
                if let n = chatStore.unread[role], n > 0 {
                    Text("(\(n))")
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .overlay(Rectangle().stroke(Theme.stroke, lineWidth: 1))
    }

    private var avatar: some View {
        ZStack {
            Rectangle()
                .fill(Theme.surfaceHi)
                .frame(width: 44, height: 44)
            Rectangle()
                .stroke(accent, lineWidth: 1)
                .frame(width: 44, height: 44)
            Text(role == .pm ? "M" : "P")
                .font(Theme.mono(20, weight: .bold))
                .foregroundStyle(accent)
        }
    }

    private var handleLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(handle)
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if (chatStore.thinking[role] ?? false) {
                Text("[typing…]")
                    .font(Theme.mono(10))
                    .foregroundStyle(accent)
            }
        }
    }

    private var previewLine: some View {
        Group {
            if let preview = chatStore.lastMessagePreview(for: role) {
                Text(preview.text)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            } else {
                Text(role.subtitle)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textGhost)
                    .lineLimit(1)
            }
        }
    }

    private var handle: String {
        switch role {
        case .pm:  return "mac-claude@pm"
        case .swe: return "pc-claude@swe"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
