import Foundation
import Synchronization
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
        /// Avant l'heure prévue : « Fait » seulement (« Dans 1 h » ajoutait un rappel sans rien décaler).
        static let early = "EARLY"
        /// Près du lieu d'une tâche (« Me le rappeler en passant à côté »).
        static let nearby = "NEARBY"
        /// Envie proposée : une catégorie par type, pour « Lu », « Vu », « Écouté ».
        static func suggestion(_ kind: ToSee.Kind) -> String { "SUGGEST_" + kind.rawValue }
    }

    enum Action {
        static let done = "DONE"
        static let plusOneHour = "PLUS_1H"
        static let tonight = "TONIGHT"
        static let tomorrow = "TOMORROW"
        static let timePrefix = "TIME_"
        static let route = "ROUTE"
        /// Envie : ouvrir son lien (ou la fiche s'il n'y en a pas).
        static let open = "OPEN"
        /// Envie : ne plus la proposer pendant une semaine.
        static let later = "LATER"
    }

    static let askTimeChoices = [9 * 60, 12 * 60, 15 * 60, 18 * 60]

    /// Relances sur cet appareil : seulement s'il est l'appareil choisi (voir `ReminderDevice`).
    static var isEnabledOnThisDevice: Bool { ReminderDevice.chosen == .current }

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
        let open = UNNotificationAction(identifier: Action.open, title: "Ouvrir", options: .foreground,
                                        icon: UNNotificationActionIcon(systemImageName: "arrow.up.right.square"))
        let later = UNNotificationAction(identifier: Action.later, title: "Pas maintenant",
                                         icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
        let suggestions = EnvieSuggestions.kinds.map { kind in
            UNNotificationCategory(identifier: Category.suggestion(kind), actions: [
                open,
                UNNotificationAction(identifier: Action.done, title: kind.doneTitle,
                                     icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")),
                later,
            ], intentIdentifiers: [])
        }
        center.setNotificationCategories(Set(suggestions).union([
            UNNotificationCategory(identifier: Category.task, actions: [done, plusOne, tonight, tomorrow], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.askTime, actions: times, intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.digest, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.early, actions: [done], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.nearby, actions: [done, tomorrow], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.departure, actions: [
                UNNotificationAction(identifier: Action.route, title: "Itinéraire", options: .foreground,
                                     icon: UNNotificationActionIcon(systemImageName: "map")),
                done,
            ], intentIdentifiers: []),
        ]))
    }

    /// « Pas maintenant » sur une suggestion : l'envie n'est plus proposée pendant une semaine.
    func skipSuggestion(_ taskID: String, now: Date = .now) {
        var history = EnvieHistory.load(from: AppGroup.defaults)
        history.skip(taskID, now: now)
        history.save(to: AppGroup.defaults)
    }

    /// Demandée une fois l'utilité expliquée (écran d'accueil), jamais au lancement à froid.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func apply(tasks: [PlannableTask], inboxCount: Int, finishedTaskIDs: Set<String>, overdueNow: Int) async {
        let now = Date.now
        var history = EnvieHistory.load(from: AppGroup.defaults)
        history.recordShown(now: now)
        history.keepOnly(Set(tasks.filter { $0.toSee != nil }.map(\.id)), now: now)
        let plan = Self.isEnabledOnThisDevice
            ? ReminderPlanner(calendar: .current, settings: settings, history: history).plan(tasks: tasks, inboxCount: inboxCount, now: now)
            : []
        history.planned = Dictionary(plan.filter { $0.kind == .suggestion }.compactMap { r in r.taskID.map { ($0, r.fireDate) } },
                                     uniquingKeysWith: min)
        history.save(to: AppGroup.defaults)

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

    /// La photo jointe à la tâche, si elle est déjà sur l'appareil.
    private static func imageAttachment(_ id: String) -> UNNotificationAttachment? {
        let piece = TacheHA.Piece(id: id, nom: "", type: "image/jpeg", taille: 0)
        guard let local = PiecesJointes.local(piece) else { return nil }
        let copie = FileManager.default.temporaryDirectory.appending(path: "\(id)-\(UUID().uuidString).jpg")
        guard (try? FileManager.default.copyItem(at: local, to: copie)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: id, url: copie)
    }

    private func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.subtitle = reminder.subtitle
        content.body = reminder.body
        content.sound = .default
        content.badge = NSNumber(value: reminder.badge)
        content.interruptionLevel = reminder.timeSensitive ? .timeSensitive : .active
        // Une envie proposée n'insiste pas : sans son, dans le centre de notifications.
        if reminder.kind == .suggestion {
            content.sound = nil
            content.interruptionLevel = .passive
        }
        content.threadIdentifier = reminder.taskID ?? "digest"
        content.categoryIdentifier = switch reminder.kind {
        case .digest: Category.digest
        case .askTime: Category.askTime
        case .departure: Category.departure
        // Avant l'heure : Itinéraire s'il y a une adresse, sinon Fait seulement.
        case .advance, .toSeeOpening, .toSeeEnding, .toSeeLastWeekend, .eventWeek, .eventEve, .eventSoon:
            reminder.hasPlace ? Category.departure : Category.early
        case .suggestion:
            Category.suggestion(ToSee.Kind.allCases.first { $0.title == reminder.subtitle } ?? .read)
        default: Category.task
        }
        if let taskID = reminder.taskID { content.userInfo = ["taskID": taskID] }
        // Image jointe (P9-K) : copiée, car iOS déplace le fichier d'une pièce jointe de notification.
        if let id = reminder.imageID, let attachment = Self.imageAttachment(id) { content.attachments = [attachment] }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }
}
