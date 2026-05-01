// Susurro — System notification delivery for read events
import UserNotifications

@MainActor
enum SusurroNotifier {

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationAuthorizationStatus()
        guard status == .notDetermined else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            AppLogger.app.info("notification permission granted=\(granted, privacy: .public)")
        } catch {
            AppLogger.app.error("notification permission request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func notifySuccess(title: String, durationMs: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Now reading"
        content.body = "\u{201C}\(title)\u{201D} is ready (\(durationMs / 1000)s)"
        content.sound = .default
        content.userInfo = ["susurro_action": "showTranscript"]
        deliver(content, identifier: "susurro.success.\(UUID().uuidString)")
    }

    static func notifyError(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Couldn\u{2019}t read"
        content.body = reason
        content.sound = .default
        // no userInfo action for errors — click does nothing
        deliver(content, identifier: "susurro.error.\(UUID().uuidString)")
    }

    static func notifyReplace(previousTitle: String?, newTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Susurro"
        let prev: String
        if let t = previousTitle, !t.isEmpty {
            prev = "'\(t)'"
        } else {
            prev = "previous"
        }
        content.body = "Stopped \(prev) \u{00B7} Now reading: '\(newTitle)'"
        content.userInfo = ["susurro_action": "showTranscript"]
        deliver(content, identifier: "susurro.replace.\(UUID().uuidString)")
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationAuthorizationStatus()
    }

    // MARK: - Private

    private static func deliver(_ content: UNMutableNotificationContent, identifier: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.app.error("notification delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Convenience extension

private extension UNUserNotificationCenter {
    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}
