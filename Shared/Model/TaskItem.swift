import Foundation
import SwiftData

/// Copie locale d'une tâche Google Tasks (liste « Mes tâches »).
@Model
final class TaskItem {
    /// Identifiant Google ; `nil` tant qu'une tâche créée dans l'app n'a pas été envoyée.
    @Attribute(.unique) var localID: UUID
    var googleID: String?
    var title: String
    /// Notes saisies par l'utilisateur, sans la ligne d'heure gérée par l'app.
    var notes: String
    /// Début du jour d'échéance, dans le fuseau local.
    var dueDay: Date?
    /// Heure d'échéance en minutes depuis minuit (stockée dans les notes côté Google).
    var dueMinutes: Int?
    /// Catégorie (ligne « 🏷 » des notes côté Google).
    var category: String?
    var isCompleted: Bool
    var completedAt: Date?
    var snoozedUntil: Date?
    var isTrashed: Bool
    /// Modifiée localement et pas encore envoyée à Google.
    var isDirty: Bool
    var updatedAt: Date

    init(title: String, notes: String = "", dueDay: Date? = nil, dueMinutes: Int? = nil) {
        localID = UUID()
        self.title = title
        self.notes = notes
        self.dueDay = dueDay
        self.dueMinutes = dueMinutes
        isCompleted = false
        isTrashed = false
        isDirty = true
        updatedAt = .now
    }

    /// Instant de l'échéance : l'heure si connue, sinon la fin du jour.
    func dueInstant(calendar: Calendar = .current) -> Date? {
        guard let dueDay else { return nil }
        if let dueMinutes {
            return calendar.date(bySettingHour: dueMinutes / 60, minute: dueMinutes % 60, second: 0, of: dueDay)
        }
        return calendar.date(byAdding: .day, value: 1, to: dueDay)
    }

    func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let due = dueInstant(calendar: calendar) else { return false }
        return due < now
    }

    /// À trier : pas de date, ou une date sans heure.
    var needsTriage: Bool { dueDay == nil || dueMinutes == nil }

    func markChanged() {
        isDirty = true
        updatedAt = .now
    }

    func plannable(calendar: Calendar = .current) -> PlannableTask {
        PlannableTask(
            id: localID.uuidString,
            title: title,
            dueDay: dueDay.map { calendar.dateComponents([.year, .month, .day], from: $0) },
            dueMinutes: dueMinutes,
            snoozedUntil: snoozedUntil)
    }
}
