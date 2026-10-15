import Foundation

extension TacheHA {
    /// La tâche locale, telle qu'envoyée à HA.
    init(_ item: TaskItem) {
        self.init(titre: item.title)
        notes = item.notes
        jour = Self.jour(item.dueDay)
        heure = item.dueDay == nil ? nil : Self.heure(item.dueMinutes)
        categorie = item.category
        priorite = item.priorityRaw
        tags = item.tags
        relances = item.remindersRaw
        fait = item.isCompleted
        faitLe = item.isCompleted ? Self.timestamp(item.completedAt ?? .now) : nil
        googleID = item.googleID
    }

    /// Recopie dans la tâche locale ; une échéance déplacée efface le report en cours.
    func apply(to item: TaskItem) {
        let day = day()
        let minutes = day == nil ? nil : minutes
        if day != item.dueDay || minutes != item.dueMinutes { item.snoozedUntil = nil }
        item.title = titre
        item.notes = notes
        item.dueDay = day
        item.dueMinutes = minutes
        item.category = categorie
        item.priority = priorite.flatMap(TaskPriority.init(rawValue:)) ?? .normal
        item.tags = tags
        item.remindersRaw = relances
        item.isCompleted = fait
        item.completedAt = fait ? (Self.date(faitLe) ?? item.completedAt ?? .now) : nil
        if let googleID { item.googleID = googleID }
        item.isDirty = false
    }
}
