import ActivityKit
import Foundation
import UIKit

/// Démarrage de l'activité en direct : un seul essai par passage au premier plan (28/10/2026).
/// iOS refuse `Activity.request` quand l'app n'est pas au premier plan (« Target is not foreground ») : le 27/10 à
/// 7 h 00, les synchros en arrière-plan (push de la vigie, réveil iOS) l'ont tenté 8 fois. Désormais : rien en
/// arrière-plan, un essai à l'ouverture, et s'il échoue, plus rien avant la prochaine ouverture (une ligne au journal).
/// Code pur, testé (`ActiviteDemarrageTests`).
nonisolated struct DemarrageActivite: Equatable, Sendable {
    /// Essai déjà fait depuis le dernier passage au premier plan.
    private(set) var essaye = false

    /// Faut-il appeler `Activity.request` maintenant ? Oui une seule fois, et seulement au premier plan.
    mutating func autoriser(auPremierPlan: Bool) -> Bool {
        guard auPremierPlan, !essaye else { return false }
        essaye = true
        return true
    }

    /// Retour au premier plan, ou activité en place (elle pourra être redémarrée si elle se termine) : nouvel essai permis.
    mutating func reinitialiser() { essaye = false }
}

/// Garde une seule activité en direct, avec les tâches les plus urgentes :
/// en retard d'abord, puis celles prévues dans les deux prochaines heures.
/// Selon le profil de la priorité : dès le jour prévu (Urgente, d'origine), peu avant, ou jamais (Basse).
/// Les urgentes passent devant.
/// Les tâches reportées passent après les autres.
final class LiveActivityManager {
    static let maxItems = 3
    private let upcomingWindow: TimeInterval = 2 * 3600
    private var demarrage = DemarrageActivite()
    private var observateur: (any NSObjectProtocol)?

    init() {
        // Chaque retour au premier plan permet un nouvel essai (et un seul).
        observateur = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.demarrage.reinitialiser() }
        }
    }

    func refresh(tasks: [TaskItem], settings: ReminderSettings, now: Date = .now) {
        let state = urgentState(tasks: tasks, settings: settings, now: now)
        Task { await apply(state, now: now) }
    }

    private func urgentState(tasks: [TaskItem], settings: ReminderSettings, now: Date) -> TaskActivityAttributes.ContentState? {
        let urgent = tasks
            .compactMap { item -> TaskActivityAttributes.ContentState.Item? in
                let mode = settings[item.priority].liveActivity
                guard mode != .never, !item.estPourInfo, let due = item.dueInstant(), let day = item.dueDay,
                      ActivityHiding.hiddenUntil(item.localID.uuidString, now: now) == nil else { return nil }
                let isUrgent = item.priority == .urgent
                guard due.timeIntervalSince(now) <= upcomingWindow
                        || (mode == .always && day <= Calendar.current.startOfDay(for: now)) else { return nil }
                let route = TaskContact(notes: item.notes)?.address
                    .flatMap { TravelTimes.mapsURL(to: $0, settings: settings.departure) }
                return .init(id: item.localID.uuidString, title: item.title, due: due,
                             hasTime: item.dueMinutes != nil, snoozedUntil: item.snoozedUntil, isUrgent: isUrgent,
                             routeURL: route)
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
        // (et 2 h avant l'heure, quand le second bouton passe de « Plus tard » à « Itinéraire »).
        let changes = state.items.flatMap { [$0.due, $0.snoozedUntil, $0.due.addingTimeInterval(-2 * 3600)].compactMap { $0 } }
            .filter { $0 > now }
        let content = ActivityContent(state: state, staleDate: changes.min())

        if let activity = current.first {
            demarrage.reinitialiser()
            await activity.update(content)
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled,
                  demarrage.autoriser(auPremierPlan: UIApplication.shared.applicationState == .active) {
            // Ne fonctionne qu'avec l'app au premier plan : un essai par ouverture, jamais en arrière-plan.
            Journal.essayer(.systeme, "Démarrage de l'activité en direct") {
                try Activity.request(attributes: TaskActivityAttributes(), content: content)
            }
        }
    }
}
