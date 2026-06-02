import Foundation
import UserNotifications
import UIKit

/// Thin wrapper around UNUserNotificationCenter for ZeeChat. Fires a
/// local notification when an inbound chat message arrives, updates the
/// app badge with the total unread count, and clears the badge when the
/// user opens a thread.
///
/// Local notifications fire reliably in foreground/background. They do
/// NOT fire when the app is fully suspended unless BGAppRefreshTask
/// wakes the process and triggers a refresh — see `BackgroundRefresh`.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private var authorized: Bool = false

    /// Ask once at app start. Quiet failure if the user denies — we just
    /// don't fire notifications, the chat still works via in-app polling.
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        Task { @MainActor in self.authorized = granted }
                    }
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in self.authorized = true }
            default:
                Task { @MainActor in self.authorized = false }
            }
        }
    }

    /// Fire a local notification for an inbound message. No-op if the
    /// app is currently foregrounded with this thread visible — caller
    /// can suppress via `suppress: true`.
    func notifyInbound(_ message: DispatchMessage, from role: ContactRole, suppress: Bool = false) {
        guard authorized, !suppress else { return }
        let content = UNMutableNotificationContent()
        content.title = role.displayName
        content.body = String(message.body.prefix(140))
        content.sound = .default
        content.userInfo = [
            "role": role.rawValue,
            "messageId": message.id,
        ]
        let req = UNNotificationRequest(
            identifier: "zeechat.\(message.id)",
            content: content,
            trigger: nil  // fire immediately
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    /// Update the app badge to the total unread count across all threads.
    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }
}
