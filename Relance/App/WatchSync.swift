import Foundation
import WatchConnectivity

/// Relais iPhone ↔ montre. L'iPhone envoie la liste des tâches ; la montre renvoie
/// ses actions (fait, reporter, nouvelle tâche), que l'iPhone applique puis synchronise avec Google.
final class WatchSync: NSObject, WCSessionDelegate {
    private let store: TaskStore

    init(store: TaskStore) {
        self.store = store
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Envoie l'état courant. `applicationContext` ne garde que le dernier envoi : pas d'empilement.
    func send(_ tasks: [TaskItem]) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }

        let payload = tasks
            .filter { !$0.isCompleted && !$0.isTrashed }
            .map { WatchTask(id: $0.localID.uuidString, title: $0.title, due: $0.dueInstant(),
                             hasTime: $0.dueMinutes != nil, snoozedUntil: $0.snoozedUntil) }
        try? session.updateApplicationContext([WatchLink.tasksKey: WatchLink.encode(payload)])
        // La complication suit l'état en retard : on la prévient, dans la limite du budget quotidien d'Apple.
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo([WatchLink.tasksKey: WatchLink.encode(payload)])
        }
    }

    // MARK: - Actions venues de la montre

    /// La montre envoie sans attendre de réponse : c'est cette variante qui est appelée.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let message = SendableMessage(message)
        Task { @MainActor in await handle(message.value) }
    }

    /// Envoyé en file d'attente quand l'iPhone n'était pas joignable.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let message = SendableMessage(userInfo)
        Task { @MainActor in await handle(message.value) }
    }

    private func handle(_ message: [String: Any]) async {
        guard let raw = message[WatchLink.actionKey] as? String, let action = WatchLink.Action(rawValue: raw) else { return }
        switch action {
        case .complete, .snooze:
            guard let id = (message[WatchLink.idKey] as? String).flatMap(UUID.init(uuidString:)),
                  let item = store.task(id) else { return }
            if action == .complete {
                store.complete(item)
            } else {
                store.snooze(item, until: .now.addingTimeInterval(3600))
            }
        case .add:
            guard let title = message[WatchLink.titleKey] as? String, !title.isEmpty else { return }
            let due = message[WatchLink.dueKey] as? Date
            let hasTime = message[WatchLink.hasTimeKey] as? Bool ?? false
            let calendar = Calendar.current
            let minutes = due.flatMap { date -> Int? in
                guard hasTime else { return nil }
                let c = calendar.dateComponents([.hour, .minute], from: date)
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
            store.add(title: title, day: due.map { calendar.startOfDay(for: $0) }, minutes: minutes)
        }
        await store.sync()
    }

    // MARK: - Cycle de vie de la session

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in send(store.activeTasks()) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Changement de montre : on réactive la session pour la nouvelle.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in send(store.activeTasks()) }
    }
}

/// Les dictionnaires WatchConnectivity ne contiennent que des types plist : on peut les passer d'un fil à l'autre.
nonisolated private struct SendableMessage: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}
