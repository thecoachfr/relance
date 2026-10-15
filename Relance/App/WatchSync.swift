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
            .map { WatchTask(id: store.isHAActive ? $0.localID.uuidString : ($0.googleID ?? $0.localID.uuidString), title: $0.title, due: $0.dueInstant(),
                             hasTime: $0.dueMinutes != nil, snoozedUntil: $0.snoozedUntil, priority: $0.priority,
                             category: $0.category, tags: $0.tags.isEmpty ? nil : $0.tags) }
        var context: [String: Any] = [WatchLink.tasksKey: WatchLink.encode(payload),
                                      WatchLink.tasksInHAKey: store.isHAActive]
        // Passe par le lien chiffré iPhone ↔ montre ; une chaîne vide dit à la montre d'oublier la connexion.
        let credentials = store.auth.watchCredentials
        context[WatchLink.refreshTokenKey] = credentials?.refreshToken ?? ""
        context[WatchLink.clientIDKey] = credentials?.clientID ?? ""
        let ha = store.isHAActive ? MemoHA.current : nil
        context[WatchLink.haURLKey] = ha?.url.absoluteString ?? ""
        context[WatchLink.haTokenKey] = ha?.token ?? ""
        try? session.updateApplicationContext(context)
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

    /// Fiche du mémo envoyée par la montre, qui attend la réponse (ajoutée, complétée…).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let message = SendableMessage(message)
        let reply = SendableReply(replyHandler)
        Task { @MainActor in
            let outcome = await handleMemo(message.value)
            reply.send([WatchLink.outcomeKey: outcome])
        }
    }

    /// Envoyé en file d'attente quand l'iPhone n'était pas joignable.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let message = SendableMessage(userInfo)
        Task { @MainActor in await handle(message.value) }
    }

    /// Enregistre une fiche du mémo venue de la montre ; renvoie `added`, `completed`, `unchanged` ou `failed`.
    private func handleMemo(_ message: [String: Any]) async -> String {
        guard let title = message[WatchLink.titleKey] as? String, !title.isEmpty else { return "failed" }
        let details = message[WatchLink.detailsKey] as? String ?? ""
        switch await store.memo.remember(title: title, details: details) {
        case .added?: return "added"
        case .completed?: return "completed"
        case .unchanged?: return "unchanged"
        case nil: return "failed"
        }
    }

    private func handle(_ message: [String: Any]) async {
        guard let raw = message[WatchLink.actionKey] as? String, let action = WatchLink.Action(rawValue: raw) else { return }
        switch action {
        case .memo:
            _ = await handleMemo(message)
            return
        case .complete, .snooze:
            guard let id = message[WatchLink.idKey] as? String,
                  let item = UUID(uuidString: id).flatMap(store.task) ?? store.task(googleID: id) else { return }
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
            let priority = (message[WatchLink.priorityKey] as? String).flatMap(TaskPriority.init(rawValue:)) ?? .normal
            _ = store.add(title: title, day: due.map { calendar.startOfDay(for: $0) }, minutes: minutes, priority: priority)
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

/// La réponse à la montre, appelée une fois depuis le fil principal.
nonisolated private struct SendableReply: @unchecked Sendable {
    let send: ([String: Any]) -> Void
    init(_ send: @escaping ([String: Any]) -> Void) { self.send = send }
}

/// Les dictionnaires WatchConnectivity ne contiennent que des types plist : on peut les passer d'un fil à l'autre.
nonisolated private struct SendableMessage: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}
