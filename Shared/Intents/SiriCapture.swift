import Foundation

/// Ajout par Siri, commun à l'iPhone et à la montre.
/// « appeler le garage vendredi à 15 h » en une réponse ; sinon Siri demande « Pour quand ? »,
/// et une réponse sans date (« sans date », « je ne sais pas ») range la tâche dans À trier.
/// « urgent » ou « pas pressé », dans l'une ou l'autre réponse, règle la priorité.
/// « … à lire / à écouter / à regarder / à voir » range une envie, sans échéance ni question.
nonisolated enum SiriCapture {
    static let whenDialog = "Pour quand ? Tu peux aussi dire « sans date »."

    struct Result: Equatable {
        var title: String
        /// Début du jour d'échéance.
        var day: Date?
        var minutes: Int?
        var priority: TaskPriority = .normal
        /// Envie dite dans la phrase (« Dune à regarder »).
        var kind: ToSee.Kind?
    }

    /// Date trouvée dans la phrase elle-même : pas besoin de demander « Pour quand ? ».
    static func needsWhen(_ text: String) -> Bool {
        guard ToSee.kind(in: text) == nil else { return false }
        return DateDetection.firstMatch(in: TaskPriority.removing(TaskPriority.detect(in: text), from: text)) == nil
    }

    static func parse(text: String, when: String?, calendar: Calendar = .current) -> Result {
        let spoken = TaskPriority.detect(in: text)
        let priority = spoken?.priority ?? when.flatMap { TaskPriority.detect(in: $0)?.priority } ?? .normal
        var text = TaskPriority.removing(spoken, from: text)
        if let found = ToSee.kind(in: text) {
            text.removeSubrange(found.range)
            var title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            title = title.prefix(1).uppercased() + title.dropFirst()
            return Result(title: title, priority: priority, kind: found.kind)
        }
        var title = text
        var match = DateDetection.firstMatch(in: text)
        if let found = match {
            let cleaned = DateDetection.title(of: text, removing: found)
            if cleaned.isEmpty { match = nil } else { title = cleaned }
        }
        if match == nil, let when { match = DateDetection.firstMatch(in: when) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.prefix(1).uppercased() + title.dropFirst()

        guard let match else { return Result(title: title, priority: priority) }
        let c = calendar.dateComponents([.hour, .minute], from: match.date)
        return Result(title: title,
                      day: calendar.startOfDay(for: match.date),
                      minutes: match.hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : nil,
                      priority: priority)
    }

    /// « C'est noté : Appeler le garage, vendredi 16 octobre à 15 h. »
    static func confirmation(_ r: Result) -> String {
        let note = switch r.priority {
        case .urgent: "C'est noté, en urgent"
        case .normal: "C'est noté"
        case .low: "C'est noté, sans urgence"
        }
        if let kind = r.kind { return "\(note) : \(r.title), \(kind.title.lowercased()). Elle t'attend dans Envies." }
        guard let day = r.day else { return "\(note) : \(r.title), sans date. Elle t'attend dans À trier." }
        var when = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if let m = r.minutes { when += " à " + ReminderPlanner.formatTime(m) }
        return "\(note) : \(r.title), \(when)."
    }
}
