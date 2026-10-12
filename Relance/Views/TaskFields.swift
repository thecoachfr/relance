import Foundation

/// Champs modifiables d'une tâche, pour les formulaires.
/// Le formulaire garde l'état chargé à l'ouverture (`base`) : à l'enregistrement, seuls les champs que
/// l'utilisateur a changés sont repris ; les autres gardent la valeur actuelle de la tâche. Ainsi une
/// modification arrivée entre-temps (synchro, routine de tri, autre appareil) n'est jamais écrasée.
struct TaskFields: Equatable {
    var title: String
    var notes: String
    var day: Date?
    var minutes: Int?
    var category: String?
    var priority: TaskPriority
    var reminders: ReminderOverride?
    var tags: [String]

    @MainActor init(_ item: TaskItem) {
        title = item.title
        notes = item.notes
        day = item.dueDay
        minutes = item.dueMinutes
        category = item.category
        priority = item.priority
        reminders = item.reminderOverride
        tags = item.tags
    }

    init(title: String, notes: String, day: Date?, minutes: Int?, category: String?,
         priority: TaskPriority, reminders: ReminderOverride?, tags: [String]) {
        (self.title, self.notes, self.day, self.minutes) = (title, notes, day, minutes)
        (self.category, self.priority, self.reminders, self.tags) = (category, priority, reminders, tags)
    }

    /// `self` = saisie, `base` = état à l'ouverture, `current` = tâche maintenant.
    func merged(base: TaskFields, current: TaskFields) -> TaskFields {
        func pick<T: Equatable>(_ path: KeyPath<TaskFields, T>) -> T {
            self[keyPath: path] != base[keyPath: path] ? self[keyPath: path] : current[keyPath: path]
        }
        // Date et heure vont ensemble : on les reprend ensemble.
        let dateChanged = day != base.day || minutes != base.minutes
        return TaskFields(title: pick(\.title), notes: pick(\.notes),
                          day: dateChanged ? day : current.day, minutes: dateChanged ? minutes : current.minutes,
                          category: pick(\.category), priority: pick(\.priority),
                          reminders: pick(\.reminders), tags: pick(\.tags))
    }
}

extension TaskStore {
    /// Enregistre `fields` si quelque chose change par rapport à la tâche.
    @MainActor func save(_ fields: TaskFields, to item: TaskItem) {
        guard fields != TaskFields(item) else { return }
        update(item, title: fields.title, notes: fields.notes, day: fields.day, minutes: fields.minutes,
               category: .some(fields.category), priority: fields.priority, reminders: .some(fields.reminders),
               tags: fields.tags)
    }
}
