import AppIntents
import UIKit
import UserNotifications

/// Reçoit les touches et les boutons des notifications, y compris quand l'app est en arrière-plan.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let auth = GoogleAuth()
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    lazy var store = TaskStore(auth: auth, inMemory: Self.isDemo)
    let liveActivity = LiveActivityManager()
    private var watchSync: WatchSync?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if Self.isDemo {
            auth.enableDemo()
            store.isDemo = true
            DemoData.seed(store)
        }
        #endif
        UNUserNotificationCenter.current().delegate = self
        store.scheduler.registerCategories()
        // Appareil qui relance changé ailleurs : on pose ou on retire les relances de celui-ci.
        ReminderDevice.observe { [store] in Task { await store.reschedule() } }
        // Siri, widgets et activité en direct passent par ce magasin.
        let store = store
        AppDependencyManager.shared.add(dependency: store)
        RelanceShortcuts.updateAppShortcutParameters()
        // Pushes silencieux de la vigie Home Assistant (aucune autorisation demandée à l'utilisateur).
        application.registerForRemoteNotifications()
        let watchSync = WatchSync(store: store)
        self.watchSync = watchSync
        let auth = auth
        store.travelMinutes = { item in
            await TravelTimes.shared.minutes(for: item, settings: store.scheduler.settings.departure)
        }
        store.onTasksChanged = { [liveActivity] in
            let tasks = store.activeTasks()
            liveActivity.refresh(tasks: tasks, settings: store.scheduler.settings)
            TaskIndex.update(tasks)
            CalendarLink.shared.reconcile(tasks)
            watchSync.send(tasks)
            // L'extension de partage parle à Google avec la même connexion (trousseau partagé).
            let credentials = auth.watchCredentials
            GoogleRefreshSession.shared.store(refreshToken: credentials?.refreshToken ?? "",
                                              clientID: credentials?.clientID ?? "")
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SyncLog.add("Inscrit aux push")
        Task { await PushRegistration.register(token: deviceToken) }
    }

    /// Push silencieux de la vigie : une tâche a été ajoutée ou cochée ailleurs.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        SyncLog.add("Push de la vigie reçu")
        if auth.isRestoring { await auth.restore() }
        await store.sync()
        SyncLog.add(store.lastError.map { "Synchro après push : échec (\($0))" } ?? "Synchro après push : OK")
        return store.lastError == nil ? .newData : .failed
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        SyncLog.add("Inscription aux push impossible : \(error.localizedDescription)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let idString = response.notification.request.content.userInfo["taskID"] as? String,
              let id = UUID(uuidString: idString) else { return }

        if auth.isRestoring { await auth.restore() }
        guard let item = store.task(id) else { return }
        let calendar = Calendar.current
        let now = Date.now
        let action = response.actionIdentifier

        switch action {
        case ReminderScheduler.Action.done:
            store.complete(item)
        case ReminderScheduler.Action.plusOneHour:
            store.snooze(item, until: now.addingTimeInterval(3600))
        case ReminderScheduler.Action.tonight:
            let evening = store.scheduler.settings.evening
            let tonight = calendar.date(bySettingHour: evening / 60, minute: evening % 60, second: 0, of: now)!
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
                await UIApplication.shared.open(url)
            }
            return
        case UNNotificationDefaultActionIdentifier:
            store.openedTaskID = id
        default:
            break
        }
        // Laisse le temps à la synchro de partir avant que iOS ne suspende l'app.
        await store.sync()
    }
}
