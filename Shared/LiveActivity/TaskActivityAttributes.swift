import ActivityKit
import Foundation

/// Activité en direct : les tâches les plus urgentes restent visibles sur l'écran verrouillé.
nonisolated struct TaskActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        struct Item: Codable, Hashable, Identifiable {
            var id: String
            var title: String
            /// Heure prévue, ou fin du jour pour une tâche sans heure.
            var due: Date
            var hasTime: Bool
            /// Reportée avec « Dans 1 h » : prochaine relance.
            var snoozedUntil: Date?
            var isUrgent = false
            /// Itinéraire dans Plans, si la tâche a une adresse (bouton avant l'heure).
            var routeURL: URL?

            func isSnoozed(at now: Date) -> Bool { (snoozedUntil ?? .distantPast) > now }

            /// Second bouton : avant l'heure, « Dans 1 h » ajoutait un rappel sans rien décaler.
            enum SecondAction { case later, route(URL), snooze }

            func secondAction(at now: Date) -> SecondAction {
                guard hasTime, due > now else { return .snooze }
                if let routeURL, due.timeIntervalSince(now) <= 2 * 3600 { return .route(routeURL) }
                return .later
            }
        }

        /// Au plus 3 tâches (limite de hauteur d'Apple), la plus urgente d'abord.
        var items: [Item]
        /// Nombre total de tâches urgentes, y compris celles qui ne tiennent pas à l'écran.
        var total: Int
    }
}

/// « Plus tard » : tâche retirée de l'activité en direct jusqu'à 2 h avant l'heure (ou jusqu'à l'heure).
/// Sur cet appareil seulement ; les notifications, elles, ne changent pas.
nonisolated enum ActivityHiding {
    private static let key = "activityHiddenUntil"

    static func hiddenUntil(_ id: String, now: Date = .now) -> Date? {
        let until = (AppGroup.defaults.dictionary(forKey: key)?[id] as? Double).map(Date.init(timeIntervalSince1970:))
        return until.flatMap { $0 > now ? $0 : nil }
    }

    static func hide(_ id: String, until date: Date, now: Date = .now) {
        var all = (AppGroup.defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        all = all.filter { $0.value > now.timeIntervalSince1970 }
        all[id] = date.timeIntervalSince1970
        AppGroup.defaults.set(all, forKey: key)
    }

    /// Jusqu'à 2 h avant l'heure prévue, ou jusqu'à l'heure si on y est déjà.
    static func laterDate(due: Date, now: Date = .now) -> Date {
        let window = due.addingTimeInterval(-2 * 3600)
        return window > now ? window : due
    }
}
