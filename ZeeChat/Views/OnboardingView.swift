import SwiftUI

/// First-launch sheet that explains what ZeeChat is, who you're talking
/// to, how tokens work, and how to get them. Three short pages, then a
/// "Got it" button that hands off to Settings for token entry.
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var page: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                page1.tag(0)
                page2.tag(1)
                page3.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(action: handleAction) {
                Text(page < 2 ? "Next" : "Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .background(Color(.systemBackground))
    }

    private func handleAction() {
        if page < 2 {
            withAnimation { page += 1 }
        } else {
            UserDefaults.standard.set(true, forKey: "zeechat.seenOnboarding")
            onDone()
        }
    }

    private var page1: some View {
        OnboardingPage(
            symbol: "bubble.left.and.bubble.right.fill",
            title: "Chat with your Claudes",
            detail: "ZeeChat is a direct line to your two Claude instances — Mac PM and PC SWE. Send a message, get a reply. Works anywhere with internet via Tailscale."
        )
    }

    private var page2: some View {
        OnboardingPage(
            symbol: "lock.shield.fill",
            title: "Per-daemon tokens",
            detail: "Each Claude has its own chat token — your phone holds both. Trust domains stay split: the Mac token can't talk to PC and vice versa. Tokens are stored in iOS Keychain, never synced to iCloud."
        )
    }

    private var page3: some View {
        OnboardingPage(
            symbol: "bell.badge.fill",
            title: "You'll know when they reply",
            detail: "Local notifications surface new messages even when ZeeChat is closed. The badge counts unread replies. Read receipts show when Claude has seen your message; the typing bubble shows when it's composing."
        )
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 120, height: 120)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}
