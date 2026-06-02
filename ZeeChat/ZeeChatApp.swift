import SwiftUI

@main
struct ZeeChatApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var chatStore: ChatStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let s = AppSettings()
        _settings = StateObject(wrappedValue: s)
        let store = ChatStore(settings: s)
        _chatStore = StateObject(wrappedValue: store)
        BackgroundRefresh.register {
            await store.refreshOnce()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(chatStore)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                chatStore.startPolling()
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var chatStore: ChatStore
    @State private var showingSettings = false
    @State private var showingOnboarding = false
    @State private var navPath: [ContactRole] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            ContactsView(showingSettings: $showingSettings)
                .navigationDestination(for: ContactRole.self) { role in
                    ChatView(contact: role)
                }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(onDone: {
                showingOnboarding = false
                if !settings.isConfigured { showingSettings = true }
            })
            .interactiveDismissDisabled()
        }
        .onAppear {
            NotificationService.shared.requestAuthorizationIfNeeded()
            // First-launch onboarding shows when we have NO tokens AND
            // the user hasn't dismissed it before.
            let seenOnboarding = UserDefaults.standard.bool(forKey: "zeechat.seenOnboarding")
            if !seenOnboarding && !settings.isConfigured {
                showingOnboarding = true
            } else if !settings.isConfigured {
                showingSettings = true
            } else {
                chatStore.startPolling()
            }
            // Verification hook: ZEECHAT_OPEN_CONTACT=pm|swe auto-navigates to a
            // chat thread on launch so screenshot tooling can capture both
            // the Contacts list AND a Chat view without simulating taps.
            if let target = ProcessInfo.processInfo.environment["ZEECHAT_OPEN_CONTACT"],
               let role = ContactRole(rawValue: target) {
                navPath = [role]
            }
        }
        .onChange(of: showingSettings) { _, isShowing in
            if !isShowing && settings.isConfigured {
                chatStore.startPolling()
            }
        }
    }
}
