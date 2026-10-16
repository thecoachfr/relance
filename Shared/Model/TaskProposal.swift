import Foundation

/// Autre tâche annoncée par un message partagé, proposée par la routine de tri plutôt que créée (P9, 16/10) :
/// une ligne « ➕ » dans les notes, que la fiche montre avec « Créer cette tâche » et « Ignorer ».
///
///     ➕ Proposition : Intervenante ménage · 2026-10-26 · 09:30 · 🔄 Toutes les semaines : lundi
///
/// Après le titre, chaque partie est facultative : le jour (AAAA-MM-JJ), l'heure (HH:MM), la règle 🔄
/// (format de `Recurrence`). Une règle sans jour commence à sa prochaine occurrence.
nonisolated struct TaskProposal: Equatable, Sendable {
    static let marker = "➕ Proposition :"

    var title: String
    var day: Date?
    var minutes: Int?
    var recurrence: Recurrence?

    init(title: String, day: Date? = nil, minutes: Int? = nil, recurrence: Recurrence? = nil) {
        (self.title, self.day, self.minutes, self.recurrence) = (title, day, minutes, recurrence)
    }

    /// La première proposition des notes.
    init?(notes: String) {
        guard let line = notes.components(separatedBy: "\n").first(where: { Self.clean($0).hasPrefix(Self.marker) })
        else { return nil }
        self.init(line: line)
    }

    init?(line raw: String) {
        let text = Self.clean(raw)
        guard text.hasPrefix(Self.marker) else { return nil }
        let parts = text.dropFirst(Self.marker.count).components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let title = parts.first, !title.isEmpty else { return nil }
        self.title = title
        for part in parts.dropFirst() {
            if part.hasPrefix(Recurrence.marker) {
                recurrence = Recurrence(line: part)
            } else if part.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil {
                day = Self.dayFormat.date(from: part)
            } else if let m = part.wholeMatch(of: /(\d{1,2})[:h](\d{2})/), let h = Int(m.1), let mn = Int(m.2), h < 24, mn < 60 {
                minutes = h * 60 + mn
            }
        }
    }

    /// Jour de la tâche à créer : celui de la ligne, sinon la prochaine occurrence de la règle (aujourd'hui compris).
    func startDay(today: Date = .now, calendar: Calendar = .current) -> Date? {
        if let day { return calendar.startOfDay(for: day) }
        guard let recurrence else { return nil }
        let todayStart = calendar.startOfDay(for: today)
        if case .weekly(_, let days) = recurrence, !days.isEmpty {
            // La règle hebdomadaire tombe-t-elle aujourd'hui ? Sinon, son prochain jour.
            if days.contains(calendar.component(.weekday, from: todayStart)) { return todayStart }
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        return recurrence.nextDay(after: yesterday, done: yesterday, calendar: calendar)
    }

    /// « Lundi 26 octobre à 9:30 · Toutes les semaines : lundi »
    func summary(today: Date = .now) -> String {
        var parts: [String] = []
        if let day = startDay(today: today) {
            let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            var text = date.prefix(1).uppercased() + date.dropFirst()
            if let minutes { text += String(format: " à %d:%02d", minutes / 60, minutes % 60) }
            parts.append(text)
        }
        if let recurrence { parts.append(recurrence.text) }
        return parts.joined(separator: " · ")
    }

    /// Notes de la tâche à créer : seulement la règle de répétition.
    var notes: String { recurrence?.line ?? "" }

    /// Les notes sans la proposition (créée ou ignorée).
    static func removing(from notes: String) -> String {
        guard let index = notes.components(separatedBy: "\n").firstIndex(where: { clean($0).hasPrefix(marker) }) else { return notes }
        var lines = notes.components(separatedBy: "\n")
        lines.remove(at: index)
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func clean(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
    }
}
