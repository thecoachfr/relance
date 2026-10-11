import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Côté montre : dernière liste reçue de l'iPhone, et envoi des actions.
/// Les actions sont appliquées tout de suite à l'écran, puis confirmées par l'iPhone.
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    static let snapshotKey = "watchTasks"
    /// Partagé avec la complication (même identifiant d'App Group que sur l'iPhone, conteneur propre à la montre).
    static let defaults = UserDefaults(suiteName: "group.fr.alexandrefau.relance") ?? .standard

    private(set) var tasks: [WatchTask] = WatchStore.loadSnapshot()
    private(set) var lastUpdate: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Actions

    func complete(_ task: WatchTask) {
        tasks.removeAll { $0.id == task.id }
        save()
        send([WatchLink.actionKey: WatchLink.Action.complete.rawValue, WatchLink.idKey: task.id])
    }

    func snooze(_ task: WatchTask) {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i].snoozedUntil = .now.addingTimeInterval(3600)
            save()
        }
        send([WatchLink.actionKey: WatchLink.Action.snooze.rawValue, WatchLink.idKey: task.id])
    }

    func add(title: String, due: Date?, hasTime: Bool) {
        var message: [String: Any] = [
            WatchLink.actionKey: WatchLink.Action.add.rawValue,
            WatchLink.titleKey: title,
            WatchLink.hasTimeKey: hasTime,
        ]
        if let due { message[WatchLink.dueKey] = due }
        send(message)
    }

    /// Message direct si l'iPhone répond, sinon file d'attente livrée dès qu'il redevient joignable.
    private func send(_ message: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in session.transferUserInfo(message) }
        } else {
            session.transferUserInfo(message)
        }
    }

    // MARK: - Réception

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let tasks = WatchLink.decode(applicationContext[WatchLink.tasksKey] as? Data)
        Task { @MainActor in self.receive(tasks) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let tasks = WatchLink.decode(userInfo[WatchLink.tasksKey] as? Data)
        Task { @MainActor in self.receive(tasks) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        guard let data = context[WatchLink.tasksKey] as? Data else { return }
        let tasks = WatchLink.decode(data)
        Task { @MainActor in self.receive(tasks) }
    }

    private func receive(_ tasks: [WatchTask]) {
        self.tasks = tasks
        lastUpdate = .now
        save()
    }

    // MARK: - Copie locale (partagée avec la complication)

    private func save() {
        Self.defaults.set(WatchLink.encode(tasks), forKey: Self.snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func loadSnapshot() -> [WatchTask] {
        WatchLink.decode(Self.defaults.data(forKey: snapshotKey))
    }
}
