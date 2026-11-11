import AppKit
import UserNotifications

/// Cycle de vie de l'app Mac : synchro à l'ouverture, au réveil, au retour dans l'app, et régulière par
/// `NSBackgroundActivityScheduler` (5 min fenêtre ouverte ou Mac qui relance, 15 min sinon, avec tolérance : macOS
/// regroupe ou diffère) ; boutons des notifications (si les relances sont activées sur ce Mac).
/// Avant le 11/11/2026 : une boucle de 60 s tournait tant que l'app vivait, fenêtre fermée comprise (B1).
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let mainWindowID = "main"
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    let auth = GoogleAuth()
    lazy var store = TaskStore(auth: auth, inMemory: Self.isDemo)
    let status = MenuBarStatus()
    private var lastSync = Date.distantPast
    private var synchroReguliere: NSBackgroundActivityScheduler?

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
                self.planifierSynchro()
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
        status.source = { store.activeTasks() }
        status.update(store.activeTasks())

        Task {
            if !Self.isDemo { await auth.restore() }
            await sync("Ouverture de l'app")
        }
        // Le compteur de la barre des menus se recalcule seul à la prochaine échéance (`MenuBarStatus`), plus chaque minute.
        planifierSynchro()
        // Fenêtre ouverte ou fermée : la synchro régulière change de rythme.
        for nom in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: nom, object: nil, queue: .main) { [weak self] _ in
                // Après la fermeture effective (willClose arrive avant que la fenêtre ne soit cachée).
                Task { @MainActor in self?.planifierSynchro() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.sync("Réveil du Mac")
                self?.status.update(self?.store.activeTasks() ?? [])
            }
        }
    }

    /// Fenêtre principale visible (pas seulement la barre des menus).
    private var fenetreVisible: Bool {
        NSApp.windows.contains { $0.identifier?.rawValue == Self.mainWindowID && $0.isVisible }
    }

    /// (Re)programme la synchro régulière au rythme voulu ; rien si le rythme n'a pas changé.
    private func planifierSynchro() {
        let intervalle = CadenceMac.intervalle(fenetreVisible: fenetreVisible,
                                               relancesIci: ReminderScheduler.isEnabledOnThisDevice)
        if let actuelle = synchroReguliere, actuelle.interval == intervalle { return }
        synchroReguliere?.invalidate()
        let activite = NSBackgroundActivityScheduler(identifier: "fr.alexandrefau.relance.mac.synchro")
        activite.repeats = true
        activite.interval = intervalle
        activite.tolerance = CadenceMac.tolerance(intervalle)
        activite.qualityOfService = .utility
        activite.schedule { @Sendable [weak self] fini in
            Task { @MainActor in
                await self?.syncReguliere()
                fini(.finished)
            }
        }
        synchroReguliere = activite
    }

    private func syncReguliere() async {
        planifierSynchro()   // fenêtre fermée entre-temps, ou appareil qui relance changé
        // Une synchro récente (ouverture, retour dans l'app, réveil) suffit.
        guard Date.now.timeIntervalSince(lastSync) >= CadenceMac.ecartMinimal else { return }
        await sync("Synchro régulière")
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
            if let address = TaskContact(notes: item.notes)?.destination,
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

/// Rythme de la synchro régulière du Mac (11/11/2026).
enum CadenceMac {
    /// Fenêtre ouverte ou Mac qui relance : 5 min (comme avant). Sinon, seule la barre des menus montre les tâches :
    /// 15 min suffisent (elle se resynchronise aussi au réveil du Mac et au retour dans l'app).
    static func intervalle(fenetreVisible: Bool, relancesIci: Bool) -> TimeInterval {
        fenetreVisible || relancesIci ? 5 * 60 : 15 * 60
    }

    /// La moitié de l'intervalle : macOS peut regrouper la synchro avec d'autres réveils.
    static func tolerance(_ intervalle: TimeInterval) -> TimeInterval { intervalle / 2 }

    /// Pas de synchro régulière moins de 2 min après une autre.
    static let ecartMinimal: TimeInterval = 2 * 60
}

/// Ce qu'affiche l'icône de la barre des menus : le nombre de tâches en retard. Recalculé quand les tâches changent
/// et à la prochaine échéance seulement (un minuteur unique avec 30 s de tolérance), au lieu de chaque minute.
@Observable
final class MenuBarStatus {
    private(set) var overdue = 0
    @ObservationIgnored private var prochain: Task<Void, Never>?
    /// Tâches actives relues à l'échéance (jamais celles d'avant, qui ont pu être supprimées).
    @ObservationIgnored var source: (() -> [TaskItem])?

    func update(_ tasks: [TaskItem], now: Date = .now) {
        let n = tasks.filter { $0.isOverdue(now: now) }.count
        if n != overdue { overdue = n }
        prochain?.cancel()
        prochain = nil
        let echeances = tasks.filter { !$0.isCompleted && !$0.aHoraireFixe && !$0.estPourInfo }
            .compactMap { $0.dueInstant() }
        guard let date = Self.prochaineEcheance(echeances, apres: now) else { return }
        let attente = date.timeIntervalSince(now) + 1
        prochain = Task { [weak self] in
            try? await Task.sleep(for: .seconds(attente), tolerance: .seconds(30))
            guard !Task.isCancelled, let self, let source = self.source else { return }
            self.update(source())
        }
    }

    /// La prochaine échéance après `now` : le moment où le nombre de tâches en retard peut changer.
    static func prochaineEcheance(_ echeances: [Date], apres now: Date) -> Date? {
        echeances.filter { $0 > now }.min()
    }
}
