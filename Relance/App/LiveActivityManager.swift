import ActivityKit
import Foundation

/// Garde une seule activité en direct, avec les tâches les plus urgentes :
/// en retard d'abord, puis celles prévues dans les deux prochaines heures.
/// Selon le profil de la priorité : dès le jour prévu (Urgente, d'origine), peu avant, ou jamais (Basse).
/// Les urgentes passent devant.
/// Les tâches reportées passent après les autres.
final class LiveActivityManager {
    static let maxItems = 3
    private let upcomingWindow: TimeInterval = 2 * 3600

    func refresh(tasks: [TaskItem], settings: ReminderSettings, now: Date = .now) {
        let state = urgentState(tasks: tasks, settings: settings, now: now)
        Task { await apply(state, now: now) }
    }

    private func urgentState(tasks: [TaskItem], settings: ReminderSettings, now: Date) -> TaskActivityAttributes.ContentState? {
        let urgent = tasks
            .compactMap { item -> TaskActivityAttributes.ContentState.Item? in
                let mode = settings[item.priority].liveActivity
                guard mode != .never, let due = item.dueInstant(), let day = item.dueDay else { return nil }
                let isUrgent = item.priority == .urgent
                guard due.timeIntervalSince(now) <= upcomingWindow
                        || (mode == .always && day <= Calendar.current.startOfDay(for: now)) else { return nil }
                return .init(id: item.localID.uuidString, title: item.title, due: due,
                             hasTime: item.dueMinutes != nil, snoozedUntil: item.snoozedUntil, isUrgent: isUrgent)
            }
            .sorted { a, b in
                let (sa, sb) = (a.isSnoozed(at: now), b.isSnoozed(at: now))
                if sa != sb { return !sa }
                if a.isUrgent != b.isUrgent { return a.isUrgent }
                return a.due < b.due
            }
        guard !urgent.isEmpty else { return nil }
        return .init(items: Array(urgent.prefix(Self.maxItems)), total: urgent.count)
    }

    private func apply(_ state: TaskActivityAttributes.ContentState?, now: Date) async {
        let current = Activity<TaskActivityAttributes>.activities

        guard let state else {
            for activity in current { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        // Prochain changement d'affichage : une tâche qui passe en retard ou un report qui se termine.
        let changes = state.items.flatMap { [$0.due, $0.snoozedUntil].compactMap { $0 } }.filter { $0 > now }
        let content = ActivityContent(state: state, staleDate: changes.min())

        if let activity = current.first {
            await activity.update(content)
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            // Ne fonctionne qu'avec l'app au premier plan : on réessaie à chaque ouverture.
            _ = try? Activity.request(attributes: TaskActivityAttributes(), content: content)
        }
    }
}
