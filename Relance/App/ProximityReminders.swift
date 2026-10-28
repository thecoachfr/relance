import CoreLocation
import UserNotifications

/// Rappels à l'approche d'un lieu : iOS surveille jusqu'à 20 zones de 200 m autour des tâches marquées
/// « Me le rappeler en passant à côté » (ou d'un type d'envie activé par défaut, comme les spots photo),
/// et réveille l'app quand on y entre, même fermée. Avec plus de 20 lieux, les plus proches de moi
/// (`ProximityPlanner`), recalculés aux déplacements importants. Seulement sur l'appareil qui relance,
/// avec la localisation « Toujours ».
@MainActor
final class ProximityReminders: NSObject, CLLocationManagerDelegate {
    static let shared = ProximityReminders()
    static let radius: CLLocationDistance = 200
    /// Lieux habituels (P9-H2) : plus près, pour ne pas sonner au magasin de la rue d'à côté.
    static let groupRadius: CLLocationDistance = 150
    /// Au plus un rappel par tâche et par magasin dans cet intervalle : chaque autre magasin du groupe rappelle
    /// (17/10, remarque d'Alexandre : rien au second magasin après le Franprix).
    nonisolated static let groupInterval: TimeInterval = 2 * 3600
    private static let groupNotifiedKey = "groupNotified"
    nonisolated private static let groupPrefix = "g-"
    static let maxRegions = 20
    private static let notifiedKey = "nearbyNotified"
    nonisolated private static let prefix = "relance-lieu-"

    // Surveillance de zones classique : CLMonitor (iOS 17) s'arrêtait net au lancement (12/10).
    private let location = CLLocationManager()
    private weak var store: TaskStore?
    /// Dernier recalcul déclenché par un déplacement (iOS en envoie au plus toutes les 5 min environ).
    private var lastMoveUpdate = Date.distantPast
    /// Pour ne noter dans le journal que les changements.
    private var lastSummary = ""

    var authorization: CLAuthorizationStatus { location.authorizationStatus }

    /// À appeler au lancement : iOS relance l'app à l'entrée dans une zone et prévient ce délégué.
    func start(store: TaskStore) {
        self.store = store
        location.delegate = self
    }

    /// Demandée au premier interrupteur activé : « Pendant l'utilisation », puis iOS propose « Toujours ».
    func requestAuthorization() {
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        location.requestAlwaysAuthorization()
    }

    /// Le rappel à l'approche est-il actif pour cette tâche (choix écrit, sinon défaut du type d'envie) ?
    func isOn(_ item: TaskItem) -> Bool {
        let defaults = store?.scheduler.settings.toSee ?? ToSeeSettings()
        return NearbyReminder.isOn(item.notes, byDefault: defaults.nearbyByDefault(item.toSee?.kind))
    }

    /// Zones à surveiller : quelques tâches urgentes, puis les lieux les plus proches de moi.
    func update(tasks: [TaskItem]) async {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let marked = tasks.filter { TaskContact(notes: $0.notes) != nil && isOn($0) }
        await PlaceLocator.shared.locate(PlaceLocator.addresses(of: marked))
        let allowed = authorization == .authorizedAlways || authorization == .authorizedWhenInUse
        let active = ReminderScheduler.isEnabledOnThisDevice && allowed
        var centers: [String: CLLocationCoordinate2D] = [:]
        var candidates = marked.compactMap { item -> ProximityPlanner.Candidate? in
            guard let center = PlaceLocator.shared.coordinate(for: item) else { return nil }
            centers[item.localID.uuidString] = center
            return .init(id: item.localID.uuidString, latitude: center.latitude, longitude: center.longitude,
                         urgent: item.priority == .urgent, due: item.dueInstant())
        }
        // Mes lieux (P9-H2) : chaque lieu d'un groupe rattaché à une tâche active est une zone ; urgente et échéance
        // d'après les tâches qui l'attendent.
        let lieux = store?.mesLieux ?? MesLieux.cached()
        let rattachees = tasks.map { ($0, $0.groupesDeLieux(lieux)) }.filter { !$0.1.isEmpty }
        for groupe in lieux.groupes {
            let enAttente = rattachees.filter { $0.1.contains(groupe.id) }.map(\.0)
            guard !enAttente.isEmpty else { continue }
            for lieu in groupe.lieux {
                let id = Self.groupPrefix + lieu.id
                centers[id] = CLLocationCoordinate2D(latitude: lieu.lat, longitude: lieu.lon)
                candidates.append(.init(id: id, latitude: lieu.lat, longitude: lieu.lon,
                                        urgent: enAttente.contains { $0.priority == .urgent },
                                        due: enAttente.compactMap { $0.dueInstant() }.min()))
            }
        }
        let here = location.location.map { (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        let chosen = active ? ProximityPlanner.choose(candidates, near: here, max: Self.maxRegions) : []
        let wanted = chosen.compactMap { id -> CLCircularRegion? in
            guard let center = centers[id] else { return nil }
            let radius = id.hasPrefix(Self.groupPrefix) ? Self.groupRadius : Self.radius
            let region = CLCircularRegion(center: center, radius: radius, identifier: Self.prefix + id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            return region
        }
        // Plus de lieux que de zones : suivre les déplacements importants (antennes, peu de batterie) pour
        // garder les plus proches. Sinon, inutile.
        if active && candidates.count > Self.maxRegions {
            location.startMonitoringSignificantLocationChanges()
        } else {
            location.stopMonitoringSignificantLocationChanges()
        }
        let summary = "Rappels à l'approche : \(wanted.count) zone(s) sur \(candidates.count) lieu(x)"
        if summary != lastSummary {
            lastSummary = summary
            SyncLog.add(summary)
        }

        let current = location.monitoredRegions.filter { $0.identifier.hasPrefix(Self.prefix) }
        let keep = Set(wanted.map(\.identifier))
        for region in current where !keep.contains(region.identifier) { location.stopMonitoring(for: region) }
        let monitored = Set(current.map(\.identifier))
        for region in wanted where !monitored.contains(region.identifier) { location.startMonitoring(for: region) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        guard id.hasPrefix(Self.prefix) else { return }
        EnergyMetrics.count(.zone)
        let cle = String(id.dropFirst(Self.prefix.count))
        Task { @MainActor in
            if cle.hasPrefix(Self.groupPrefix) {
                await notifyGroup(lieuID: String(cle.dropFirst(Self.groupPrefix.count)))
            } else {
                await notify(taskID: cle)
            }
        }
    }

    /// Déplacement important : on garde les lieux les plus proches.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let store, Date.now.timeIntervalSince(lastMoveUpdate) > 120 else { return }
            lastMoveUpdate = .now
            await update(tasks: store.activeTasks())
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if let store { await update(tasks: store.activeTasks()) }
        }
    }

    /// Clé du dernier rappel d'une tâche devant un magasin.
    nonisolated static func groupKey(taskID: String, lieuID: String) -> String { taskID + "|" + lieuID }

    /// Rappels encore récents (moins de 2 h), les autres oubliés.
    nonisolated static func recentGroupNotifications(_ notified: [String: Double], now: Date) -> [String: Double] {
        notified.filter { now.timeIntervalSince1970 - $0.value < groupInterval }
    }

    /// Près d'un de mes lieux (P9-H2) : chaque tâche qui attend ce groupe, au plus une fois toutes les 2 h devant
    /// ce magasin. La notification remplace celle d'un autre magasin (une seule par tâche, la plus récente).
    private func notifyGroup(lieuID: String, now: Date = .now) async {
        guard let store, ReminderScheduler.isEnabledOnThisDevice,
              let (lieu, groupe) = store.mesLieux.lieu(lieuID) else { return }
        var notified = AppGroup.defaults.dictionary(forKey: Self.groupNotifiedKey) as? [String: Double] ?? [:]
        notified = Self.recentGroupNotifications(notified, now: now)
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let quiet = store.scheduler.settings.isQuiet(minuteOfDay: (c.hour ?? 0) * 60 + (c.minute ?? 0))
        for item in store.activeTasks() where item.groupesDeLieux(store.mesLieux).contains(groupe.id) {
            let taskID = item.localID.uuidString
            let key = Self.groupKey(taskID: taskID, lieuID: lieuID)
            guard notified[key] == nil else { continue }
            notified[key] = now.timeIntervalSince1970
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.subtitle = "Tu es près de \(lieu.nom)"
            if let liste = item.liste, !liste.articles.isEmpty {
                let restants = liste.articles.count - liste.cochés
                content.body = restants == 1 ? "1 article à prendre." : "\(restants) articles à prendre."
            } else {
                content.body = item.dueInstant().map { "Prévu " + DueText.long(due: $0, hasTime: item.dueMinutes != nil).lowercased() + "." }
                    ?? "Sans date."
            }
            content.sound = quiet ? nil : .default
            content.interruptionLevel = quiet ? .passive : .timeSensitive
            content.threadIdentifier = taskID
            content.categoryIdentifier = ReminderScheduler.Category.nearby
            content.userInfo = ["taskID": taskID]
            await Journal.essayer(.notifications, "Rappel de proximité groupé") {
                try await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "\(taskID)|groupe", content: content, trigger: nil))
            }
        }
        AppGroup.defaults.set(notified, forKey: Self.groupNotifiedKey)
    }

    /// « Tu es près de … » : une fois par jour et par tâche, discret pendant la plage silencieuse.
    private func notify(taskID: String) async {
        guard let store, ReminderScheduler.isEnabledOnThisDevice,
              let id = UUID(uuidString: taskID), let item = store.task(id), !item.isCompleted, !item.isTrashed,
              isOn(item), let contact = TaskContact(notes: item.notes) else { return }
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        var notified = AppGroup.defaults.dictionary(forKey: Self.notifiedKey) as? [String: Double] ?? [:]
        guard notified[taskID] != today else { return }
        notified = notified.filter { $0.value == today }
        notified[taskID] = today
        AppGroup.defaults.set(notified, forKey: Self.notifiedKey)

        let c = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let quiet = store.scheduler.settings.isQuiet(minuteOfDay: (c.hour ?? 0) * 60 + (c.minute ?? 0))
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.subtitle = "Tu es près de \(contact.name)"
        // Une envie : sa note (« Au couchant, en automne » pour un spot photo), sinon son type.
        let envie = item.toSee.map { toSee in toSee.note.map { $0.prefix(1).uppercased() + $0.dropFirst() + "." } ?? toSee.kind.title + "." }
        content.body = item.dueInstant().map { "Prévu " + DueText.long(due: $0, hasTime: item.dueMinutes != nil).lowercased() + "." }
            ?? envie ?? "Sans date."
        content.sound = quiet ? nil : .default
        content.interruptionLevel = quiet ? .passive : .timeSensitive
        content.threadIdentifier = taskID
        content.categoryIdentifier = ReminderScheduler.Category.nearby
        content.userInfo = ["taskID": taskID]
        await Journal.essayer(.notifications, "Rappel de proximité") {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "\(taskID)|nearby|\(Int(today))", content: content, trigger: nil))
        }
    }
}
