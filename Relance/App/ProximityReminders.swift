import CoreLocation
import UserNotifications

/// Rappels à l'approche d'un lieu : iOS surveille jusqu'à 20 zones de 200 m autour des tâches marquées
/// « Me le rappeler en passant à côté », et réveille l'app quand on y entre, même fermée.
/// Seulement sur l'appareil qui relance, avec la localisation « Toujours ».
@MainActor
final class ProximityReminders: NSObject, CLLocationManagerDelegate {
    static let shared = ProximityReminders()
    static let radius: CLLocationDistance = 200
    static let maxRegions = 20
    private static let notifiedKey = "nearbyNotified"
    nonisolated private static let prefix = "relance-lieu-"

    // Surveillance de zones classique : CLMonitor (iOS 17) s'arrêtait net au lancement (12/10).
    private let location = CLLocationManager()
    private weak var store: TaskStore?

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

    /// Zones à surveiller : tâches à faire marquées, urgentes puis les plus proches de l'échéance.
    func update(tasks: [TaskItem]) async {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let marked = tasks.filter { NearbyReminder.isOn($0.notes) && TaskContact(notes: $0.notes)?.address != nil }
        await PlaceLocator.shared.locate(marked.compactMap { TaskContact(notes: $0.notes)?.address })
        let allowed = authorization == .authorizedAlways || authorization == .authorizedWhenInUse
        let wanted: [CLCircularRegion] = (ReminderScheduler.isEnabledOnThisDevice && allowed) ? marked
            .sorted { a, b in
                if a.priority.rank != b.priority.rank { return a.priority.rank < b.priority.rank }
                return (a.dueInstant() ?? .distantFuture) < (b.dueInstant() ?? .distantFuture)
            }
            .compactMap { item -> CLCircularRegion? in
                guard let address = TaskContact(notes: item.notes)?.address,
                      let center = PlaceLocator.shared.coordinates[address] else { return nil }
                let region = CLCircularRegion(center: center, radius: Self.radius,
                                              identifier: Self.prefix + item.localID.uuidString)
                region.notifyOnEntry = true
                region.notifyOnExit = false
                return region
            }
            .prefix(Self.maxRegions).map { $0 } : []

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
        Task { @MainActor in await notify(taskID: String(id.dropFirst(Self.prefix.count))) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if let store { await update(tasks: store.activeTasks()) }
        }
    }

    /// « Tu es près de … » : une fois par jour et par tâche, discret pendant la plage silencieuse.
    private func notify(taskID: String) async {
        guard let store, ReminderScheduler.isEnabledOnThisDevice,
              let id = UUID(uuidString: taskID), let item = store.task(id), !item.isCompleted, !item.isTrashed,
              NearbyReminder.isOn(item.notes), let contact = TaskContact(notes: item.notes) else { return }
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
        content.body = item.dueInstant().map { "Prévu " + DueText.long(due: $0, hasTime: item.dueMinutes != nil).lowercased() + "." } ?? "Sans date."
        content.sound = quiet ? nil : .default
        content.interruptionLevel = quiet ? .passive : .timeSensitive
        content.threadIdentifier = taskID
        content.categoryIdentifier = ReminderScheduler.Category.nearby
        content.userInfo = ["taskID": taskID]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "\(taskID)|nearby|\(Int(today))", content: content, trigger: nil))
    }
}
