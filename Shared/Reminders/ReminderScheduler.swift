import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

/// Traduit le plan du `ReminderPlanner` en notifications locales iOS.
final class ReminderScheduler {
    /// Réglages › Relances, gardés sur cet appareil.
    var settings = ReminderSettings.load(from: AppGroup.defaults) {
        didSet { settings.save(to: AppGroup.defaults) }
    }
    private let center = UNUserNotificationCenter.current()

    enum Category {
        static let task = "TASK"
        static let askTime = "ASK_TIME"
        static let digest = "DIGEST"
        static let departure = "DEPARTURE"
    }

    enum Action {
        static let done = "DONE"
        static let plusOneHour = "PLUS_1H"
        static let tonight = "TONIGHT"
        static let tomorrow = "TOMORROW"
        static let timePrefix = "TIME_"
        static let route = "ROUTE"
    }

    static let askTimeChoices = [9 * 60, 12 * 60, 15 * 60, 18 * 60]

    private static let enabledKey = "remindersOnThisDevice"

    /// Relances sur cet appareil. Par défaut seul l'iPhone relance : sinon iPhone et iPad
    /// sonnent pour la même tâche, et un « Fait » sur l'un ne coupe l'autre qu'à la synchro suivante.
    static var isEnabledOnThisDevice: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? isPhone }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
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
            UNNotificationCategory(identifier: Category.departure, actions: [
                UNNotificationAction(identifier: Action.route, title: "Itinéraire", options: .foreground,
                                     icon: UNNotificationActionIcon(systemImageName: "map")),
                done,
            ], intentIdentifiers: []),
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
        // iOS ne répond parfois jamais à ces deux appels (observé en test) : on ne bloque pas la synchro pour du ménage.
        await Self.withTimeout(seconds: 3) {
            let center = UNUserNotificationCenter.current()
            await Self.tidyDelivered(center: center, finishedTaskIDs: finishedTaskIDs)
            try? await center.setBadgeCount(overdueNow)
        }
    }

    /// Tâche arrivée de Google avec une date mais sans heure (Google Home garde l'heure pour lui) :
    /// on la demande tout de suite, plutôt que le matin du jour prévu. En plage silencieuse, sans son.
    func askTimeNow(for tasks: [PlannableTask], now: Date = .now, calendar: Calendar = .current) async {
        guard Self.isEnabledOnThisDevice else { return }
        let c = calendar.dateComponents([.hour, .minute], from: now)
        let quiet = settings.isQuiet(minuteOfDay: (c.hour ?? 0) * 60 + (c.minute ?? 0))
        for task in tasks {
            guard let day = task.dueDay.flatMap(calendar.date(from:)),
                  day >= calendar.startOfDay(for: now),
                  let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let when = DueText.long(due: endOfDay, hasTime: false, now: now, calendar: calendar)
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = "Prévu \(when.prefix(1).lowercased() + when.dropFirst()). À quelle heure ?"
            content.sound = quiet ? nil : .default
            content.interruptionLevel = quiet ? .passive : .active
            content.threadIdentifier = task.id
            content.categoryIdentifier = Category.askTime
            content.userInfo = ["taskID": task.id]
            try? await center.add(UNNotificationRequest(identifier: "\(task.id)|askTimeNow", content: content, trigger: nil))
        }
    }

    /// Attend `operation` au plus `seconds` secondes, puis continue même si elle n'a pas répondu.
    nonisolated static func withTimeout(seconds: Double, _ operation: @escaping @Sendable () async -> Void) async {
        let resumed = Mutex(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeOnce: @Sendable () -> Void = {
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume() }
            }
            Task { await operation(); resumeOnce() }
            Task { try? await Task.sleep(for: .seconds(seconds)); resumeOnce() }
        }
    }

    /// Retire les notifications des tâches terminées, et ne garde que la plus récente par tâche.
    nonisolated private static func tidyDelivered(center: UNUserNotificationCenter, finishedTaskIDs: Set<String>) async {
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
        content.subtitle = reminder.subtitle
        content.body = reminder.body
        content.sound = .default
        content.badge = NSNumber(value: reminder.badge)
        content.interruptionLevel = reminder.timeSensitive ? .timeSensitive : .active
        content.threadIdentifier = reminder.taskID ?? "digest"
        content.categoryIdentifier = switch reminder.kind {
        case .digest: Category.digest
        case .askTime: Category.askTime
        case .departure: Category.departure
        default: Category.task
        }
        if let taskID = reminder.taskID { content.userInfo = ["taskID": taskID] }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }
}
