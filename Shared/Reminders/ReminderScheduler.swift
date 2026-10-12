import Foundation
import UIKit
import UserNotifications

/// Traduit le plan du `ReminderPlanner` en notifications locales iOS.
final class ReminderScheduler {
    var settings = ReminderSettings()
    private let center = UNUserNotificationCenter.current()

    enum Category {
        static let task = "TASK"
        static let askTime = "ASK_TIME"
        static let digest = "DIGEST"
    }

    enum Action {
        static let done = "DONE"
        static let plusOneHour = "PLUS_1H"
        static let tonight = "TONIGHT"
        static let tomorrow = "TOMORROW"
        static let timePrefix = "TIME_"
    }

    static let askTimeChoices = [9 * 60, 12 * 60, 15 * 60, 18 * 60]

    private static let enabledKey = "remindersOnThisDevice"

    /// Relances sur cet appareil. Par défaut seul l'iPhone relance : sinon iPhone et iPad
    /// sonnent pour la même tâche, et un « Fait » sur l'un ne coupe l'autre qu'à la synchro suivante.
    static var isEnabledOnThisDevice: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? (UIDevice.current.userInterfaceIdiom == .phone) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func registerCategories() {
        let done = UNNotificationAction(identifier: Action.done, title: "Fait",
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let plusOne = UNNotificationAction(identifier: Action.plusOneHour, title: "Dans 1 h",
                                           icon: UNNotificationActionIcon(systemImageName: "clock"))
        let tonight = UNNotificationAction(identifier: Action.tonight, title: "Ce soir",
                                           icon: UNNotificationActionIcon(systemImageName: "moon"))
        let tomorrow = UNNotificationAction(identifier: Action.tomorrow, title: "Demain matin",
                                            icon: UNNotificationActionIcon(systemImageName: "sunrise"))
        let times = Self.askTimeChoices.map { minutes in
            UNNotificationAction(identifier: Action.timePrefix + String(minutes),
                                 title: ReminderPlanner.formatTime(minutes),
                                 icon: UNNotificationActionIcon(systemImageName: "clock"))
        }
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.task, actions: [done, plusOne, tonight, tomorrow], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.askTime, actions: times, intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.digest, actions: [], intentIdentifiers: []),
        ])
    }

    /// Demandée une fois l'utilité expliquée (écran d'accueil), jamais au lancement à froid.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func apply(tasks: [PlannableTask], inboxCount: Int, finishedTaskIDs: Set<String>, overdueNow: Int) async {
        let plan = Self.isEnabledOnThisDevice
            ? ReminderPlanner(calendar: .current, settings: settings).plan(tasks: tasks, inboxCount: inboxCount, now: .now)
            : []

        center.removeAllPendingNotificationRequests()
        for reminder in plan {
            try? await center.add(request(for: reminder))
        }
        await tidyDelivered(finishedTaskIDs: finishedTaskIDs)
        try? await center.setBadgeCount(overdueNow)
    }

    /// Retire les notifications des tâches terminées, et ne garde que la plus récente par tâche.
    private func tidyDelivered(finishedTaskIDs: Set<String>) async {
        let delivered = await center.deliveredNotifications()
        var latestByThread: [String: UNNotification] = [:]
        var toRemove: [String] = []
        for notification in delivered {
            let thread = notification.request.content.threadIdentifier
            if finishedTaskIDs.contains(thread) {
                toRemove.append(notification.request.identifier)
            } else if let kept = latestByThread[thread] {
                let older = kept.date < notification.date ? kept : notification
                toRemove.append(older.request.identifier)
                latestByThread[thread] = kept.date < notification.date ? notification : kept
            } else {
                latestByThread[thread] = notification
            }
        }
        center.removeDeliveredNotifications(withIdentifiers: toRemove)
    }

    private func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.badge = NSNumber(value: reminder.badge)
        content.interruptionLevel = reminder.timeSensitive ? .timeSensitive : .active
        content.threadIdentifier = reminder.taskID ?? "digest"
        content.categoryIdentifier = switch reminder.kind {
        case .digest: Category.digest
        case .askTime: Category.askTime
        default: Category.task
        }
        if let taskID = reminder.taskID { content.userInfo = ["taskID": taskID] }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }
}
