import Foundation
import UserNotifications

/// Local notifications (no push entitlement needed — works on free
/// provisioning). Posts a MileIQ-style "drive tracked" notification when a
/// drive is auto-detected so classification is one lock-screen glance away.
enum NotificationService {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            NSLog("Miles: notification permission granted=\(granted)")
        }
    }

    static func notifyDriveTracked(
        miles: Double,
        endAddress: String,
        potentialDeductionDollars: Double,
        category: DriveCategory
    ) {
        let content = UNMutableNotificationContent()
        content.title = String(format: "Tracked your %.1f-mile drive", miles)
        switch category {
        case .unclassified:
            let destination = endAddress.isEmpty ? "" : " to \(endAddress)"
            content.body = String(
                format: "Was the drive%@ business or personal? It could be worth %@ if you classify it.",
                destination,
                Formatters.money(potentialDeductionDollars)
            )
        case .business:
            content.body = String(
                format: "Auto-classified as Business — %@ deduction recorded.",
                Formatters.money(potentialDeductionDollars)
            )
        case .personal:
            content.body = "Auto-classified as Personal."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Miles: failed to post notification: \(error)")
            }
        }
    }
}
