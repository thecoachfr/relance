import AppKit
import UserNotifications

/// Cycle de vie de l'app Mac : synchro à l'ouverture, toutes les 5 minutes et au réveil ;
/// boutons des notifications (si les relances sont activées sur ce Mac).
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let mainWindowID = "main"
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    let auth = GoogleAuth()
    lazy var store = TaskStore(auth: auth, inMemory: Self.isDemo)
    let status = MenuBarStatus()
    private var lastSync = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Self.isDemo {
            auth.enableDemo()
            store.isDemo = true
            DemoData.seed(store)
        }
        #endif
        UNUserNotificationCenter.current().delegate = self
        store.scheduler.registerCategories()
        // Appareil qui relance changé ailleurs : on pose ou on retire les relances du Mac.
        ReminderDevice.observe { [store] in
            Task {
                if ReminderScheduler.isEnabledOnThisDevice { _ = await store.scheduler.requestAuthorization() }
                await store.reschedule()
            }
        }
        let store = store
        let status = status
        store.travelMinutes = { item in
            await TravelTimes.shared.minutes(for: item, settings: store.scheduler.settings.departure)
        }
        store.onTasksChanged = {
            let tasks = store.activeTasks()
            CalendarLink.shared.reconcile(tasks)
            status.update(tasks)
        }
        status.update(store.activeTasks())

        Task {
            if !Self.isDemo { await auth.restore() }
            await sync("Ouverture de l'app")
        }
        // Toutes les 5 minutes ; le compteur de la barre des menus suit l'heure chaque minute.
        Task {
            var minutes = 0
            while true {
                try? await Task.sleep(for: .seconds(60))
                minutes += 1
                status.update(store.activeTasks())
                if minutes % 5 == 0 { await sync("Synchro régulière") }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.sync("Réveil du Mac") }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Au retour dans l'app, sans relancer une synchro toutes les deux secondes.
        guard Date.now.timeIntervalSince(lastSync) > 60 else { return }
        Task { await sync("Retour dans l'app") }
    }

    /// La barre des menus garde l'app ouverte quand on ferme la fenêtre.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func sync(_ reason: String) async {
        guard auth.isSignedIn else { return }
        lastSync = .now
        SyncLog.add(reason)
        await store.sync()
    }

    /// Ramène la fenêtre principale (elle peut être seulement cachée derrière les autres).
    static func showMainWindow() {
        NSApp.activate()
        NSApp.windows.first { $0.identifier?.rawValue == mainWindowID }?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let idString = response.notification.request.content.userInfo["taskID"] as? String,
              let id = UUID(uuidString: idString) else { return }
        if auth.isRestoring { await auth.restore() }
        guard let item = store.task(id) else { return }
        let now = Date.now

        switch response.actionIdentifier {
        case ReminderScheduler.Action.done:
            store.complete(item)
        case ReminderScheduler.Action.plusOneHour:
            store.snooze(item, until: now.addingTimeInterval(3600))
        case ReminderScheduler.Action.tonight:
            let evening = store.scheduler.settings.evening
            let tonight = Calendar.current.date(bySettingHour: evening / 60, minute: evening % 60, second: 0, of: now)!
            store.snooze(item, until: tonight > now ? tonight : now.addingTimeInterval(3600))
        case ReminderScheduler.Action.tomorrow:
            store.moveToTomorrow(item)
        case let a where a.hasPrefix(ReminderScheduler.Action.timePrefix):
            if let minutes = Int(a.dropFirst(ReminderScheduler.Action.timePrefix.count)) {
                store.setTime(item, minutes: minutes)
            }
        case ReminderScheduler.Action.route:
            if let address = TaskContact(notes: item.notes)?.address,
               let url = TravelTimes.mapsURL(to: address, settings: store.scheduler.settings.departure) {
                NSWorkspace.shared.open(url)
            }
            return
        case ReminderScheduler.Action.open:
            if let link = ToSee.link(in: item.notes) {
                NSWorkspace.shared.open(link)
            } else {
                store.openedTaskID = id
                Self.showMainWindow()
            }
            return
        case ReminderScheduler.Action.later:
            store.scheduler.skipSuggestion(idString)
            await store.reschedule()
            return
        case UNNotificationDefaultActionIdentifier:
            store.openedTaskID = id
            Self.showMainWindow()
            return
        default:
            return
        }
        await store.sync()
    }
}

/// Ce qu'affiche l'icône de la barre des menus : le nombre de tâches en retard.
@Observable
final class MenuBarStatus {
    private(set) var overdue = 0

    func update(_ tasks: [TaskItem], now: Date = .now) {
        overdue = tasks.filter { $0.isOverdue(now: now) }.count
    }
}
