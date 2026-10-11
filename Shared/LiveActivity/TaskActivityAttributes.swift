import ActivityKit
import Foundation

/// Activité en direct : la tâche la plus urgente reste visible sur l'écran verrouillé.
nonisolated struct TaskActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var taskID: String
        var title: String
        /// Heure prévue, ou fin du jour pour une tâche sans heure.
        var due: Date
        var hasTime: Bool
        /// Autres tâches en retard, en plus de celle affichée.
        var otherOverdue: Int
        /// Reportée avec « Dans 1 h » : prochaine relance.
        var snoozedUntil: Date? = nil
    }
}
