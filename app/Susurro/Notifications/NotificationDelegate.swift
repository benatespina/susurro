// Susurro — UNUserNotificationCenterDelegate for foreground display and action routing
import UserNotifications

extension Notification.Name {
    static let susurroShowTranscriptRequested = Notification.Name("susurroShowTranscriptRequested")
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    /// Allow banners + sound even while the app is frontmost (menu-bar agent, no main window).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Route tap on a notification to the appropriate in-app action.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let action = response.notification.request.content.userInfo["susurro_action"] as? String
        if action == "showTranscript" {
            NotificationCenter.default.post(name: .susurroShowTranscriptRequested, object: nil)
        }
    }
}
