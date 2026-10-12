import Foundation

/// Ajout par Siri, commun à l'iPhone et à la montre.
/// « appeler le garage vendredi à 15 h » en une réponse ; sinon Siri demande « Pour quand ? »,
/// et une réponse sans date (« sans date », « je ne sais pas ») range la tâche dans À trier.
nonisolated enum SiriCapture {
    static let whenDialog = "Pour quand ? Tu peux aussi dire « sans date »."

    struct Result: Equatable {
        var title: String
        /// Début du jour d'échéance.
        var day: Date?
        var minutes: Int?
    }

    /// Date trouvée dans la phrase elle-même : pas besoin de demander « Pour quand ? ».
    static func needsWhen(_ text: String) -> Bool {
        DateDetection.firstMatch(in: text) == nil
    }

    static func parse(text: String, when: String?, calendar: Calendar = .current) -> Result {
        var title = text
        var match = DateDetection.firstMatch(in: text)
        if let found = match {
            let cleaned = DateDetection.title(of: text, removing: found)
            if cleaned.isEmpty { match = nil } else { title = cleaned }
        }
        if match == nil, let when { match = DateDetection.firstMatch(in: when) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.prefix(1).uppercased() + title.dropFirst()

        guard let match else { return Result(title: title) }
        let c = calendar.dateComponents([.hour, .minute], from: match.date)
        return Result(title: title,
                      day: calendar.startOfDay(for: match.date),
                      minutes: match.hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : nil)
    }

    /// « C'est noté : Appeler le garage, vendredi 16 octobre à 15 h. »
    static func confirmation(_ r: Result) -> String {
        guard let day = r.day else { return "C'est noté : \(r.title), sans date. Elle t'attend dans À trier." }
        var when = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if let m = r.minutes { when += " à " + ReminderPlanner.formatTime(m) }
        return "C'est noté : \(r.title), \(when)."
    }
}
