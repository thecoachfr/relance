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

            func isSnoozed(at now: Date) -> Bool { (snoozedUntil ?? .distantPast) > now }
        }

        /// Au plus 3 tâches (limite de hauteur d'Apple), la plus urgente d'abord.
        var items: [Item]
        /// Nombre total de tâches urgentes, y compris celles qui ne tiennent pas à l'écran.
        var total: Int
    }
}
