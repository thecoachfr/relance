import ActivityKit
import Foundation

/// Garde une seule activité en direct, sur la tâche la plus urgente :
/// la plus en retard, sinon celle prévue dans les deux prochaines heures.
final class LiveActivityManager {
    private let upcomingWindow: TimeInterval = 2 * 3600

    func refresh(tasks: [TaskItem], now: Date = .now) {
        let state = urgentState(tasks: tasks, now: now)
        Task { await apply(state) }
    }

    /// Les tâches reportées cèdent la place ; s'il ne reste qu'elles, on affiche la première avec son report.
    private func urgentState(tasks: [TaskItem], now: Date) -> TaskActivityAttributes.ContentState? {
        let dated = tasks
            .compactMap { item in item.dueInstant().map { (item, $0) } }
            .sorted { $0.1 < $1.1 }
        let isSnoozed = { (item: TaskItem) in (item.snoozedUntil ?? .distantPast) > now }
        let overdue = dated.filter { $0.0.isOverdue(now: now) }
        let urgent = overdue + dated.filter { !$0.0.isOverdue(now: now) && $0.1.timeIntervalSince(now) <= upcomingWindow }

        guard let (item, due) = urgent.first(where: { !isSnoozed($0.0) }) ?? urgent.first else { return nil }
        return .init(taskID: item.localID.uuidString, title: item.title, due: due,
                     hasTime: item.dueMinutes != nil,
                     otherOverdue: overdue.filter { $0.0 !== item }.count,
                     snoozedUntil: isSnoozed(item) ? item.snoozedUntil : nil)
    }

    private func apply(_ state: TaskActivityAttributes.ContentState?) async {
        let current = Activity<TaskActivityAttributes>.activities

        guard let state else {
            for activity in current { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        // Après l'échéance, iOS marque l'activité comme périmée : la vue passe en « en retard ».
        // À la fin d'un report aussi, pour que la vue repasse en « en retard ».
        let content = ActivityContent(state: state, staleDate: state.snoozedUntil ?? (state.due > .now ? state.due : nil))

        if let activity = current.first {
            await activity.update(content)
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            // Ne fonctionne qu'avec l'app au premier plan : on réessaie à chaque ouverture.
            _ = try? Activity.request(attributes: TaskActivityAttributes(), content: content)
        }
    }
}
