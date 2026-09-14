import AppKit
import UserNotifications

/// Used instead of the corner panel when the user turns the panel off.
@MainActor
final class NotificationsService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsService()
    nonisolated static let category = "SNAPBAR_SHOT"
    nonisolated static let copyAction = "COPY"

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let copy = UNNotificationAction(identifier: NotificationsService.copyAction, title: String(localized: "Copy"), options: [])
        let category = UNNotificationCategory(identifier: NotificationsService.category, actions: [copy], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Log.info("notifications authorization granted=\(granted)")
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(granted) } }
        }
    }

    func authorizationStatus(completion: @escaping @MainActor (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(status) } }
        }
    }

    func post(shot: Shot) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Screenshot saved")
        content.body = String(localized: "It is on the clipboard. Click Copy to copy it again.")
        content.categoryIdentifier = NotificationsService.category
        content.userInfo = ["path": shot.path]
        if let thumb = ImageTools.thumbnail(url: shot.url, maxPixel: 720) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("snapbar-note-\(shot.id.uuidString).png")
            if ImageTools.write(thumb, to: tmp, type: .png),
               let attachment = try? UNNotificationAttachment(identifier: "image", url: tmp) {
                content.attachments = [attachment]
            }
        }
        let request = UNNotificationRequest(identifier: shot.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            Log.info("notification posted error=\(error?.localizedDescription ?? "none")")
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let path = response.notification.request.content.userInfo["path"] as? String
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let path else { return }
                if action == NotificationsService.copyAction || action == UNNotificationDefaultActionIdentifier {
                    Clipboard.write(fileURL: URL(fileURLWithPath: path))
                    Log.info("notification action=copy")
                }
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
