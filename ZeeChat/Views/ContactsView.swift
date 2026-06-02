import SwiftUI

struct ContactsView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject var chatStore: ChatStore

    var body: some View {
        List {
            ForEach(ContactRole.allCases) { role in
                NavigationLink {
                    ChatView(contact: role)
                } label: {
                    ContactRow(role: role)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("ZeeChat")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await chatStore.refreshOnce() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .refreshable {
            await chatStore.refreshOnce()
        }
    }
}

struct ContactRow: View {
    @EnvironmentObject var chatStore: ChatStore
    let role: ContactRole

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(role.displayName)
                        .font(.headline)
                    if (chatStore.thinking[role] ?? false) {
                        Text("typing…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if let preview = chatStore.lastMessagePreview(for: role) {
                    Text(preview.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(role.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let ts = chatStore.lastMessagePreview(for: role)?.ts {
                    Text(Self.relativeFormatter.localizedString(for: ts, relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let n = chatStore.unread[role], n > 0 {
                    Text("\(n)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(role == .pm ? Color.blue.opacity(0.85) : Color.purple.opacity(0.85))
                .frame(width: 44, height: 44)
            Text(role == .pm ? "M" : "P")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
