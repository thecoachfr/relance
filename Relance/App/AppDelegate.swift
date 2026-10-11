import AppIntents
import UIKit
import UserNotifications

/// Reçoit les touches et les boutons des notifications, y compris quand l'app est en arrière-plan.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let auth = GoogleAuth()
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    lazy var store = TaskStore(auth: auth, inMemory: Self.isDemo)
    let liveActivity = LiveActivityManager()

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
        // Siri, widgets et activité en direct passent par ce magasin.
        let store = store
        AppDependencyManager.shared.add(dependency: store)
        RelanceShortcuts.updateAppShortcutParameters()
        // Pushes silencieux de la vigie Home Assistant (aucune autorisation demandée à l'utilisateur).
        application.registerForRemoteNotifications()
        store.onTasksChanged = { [liveActivity] in liveActivity.refresh(tasks: store.activeTasks()) }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushRegistration.register(token: deviceToken) }
    }

    /// Push silencieux de la vigie : une tâche a été ajoutée ou cochée ailleurs.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        if auth.isRestoring { await auth.restore() }
        await store.sync()
        return store.lastError == nil ? .newData : .failed
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
        case UNNotificationDefaultActionIdentifier:
            store.openedTaskID = id
        default:
            break
        }
        // Laisse le temps à la synchro de partir avant que iOS ne suspende l'app.
        await store.sync()
    }
}
