import Foundation

/// Tâche récurrente : une ligne « 🔄 » dans les notes (Google Tasks n'expose pas la répétition à son API).
/// À chaque « Fait », Relance crée la tâche suivante (l'historique reste dans « Fait »).
///
///     🔄 Tous les jours                      🔄 Tous les 2 jours
///     🔄 Toutes les semaines : lundi, jeudi  🔄 Toutes les 2 semaines
///     🔄 Tous les mois le 5                  🔄 Tous les 3 mois le dernier jour
///     🔄 Tous les mois le 1er lundi          🔄 Tous les mois le dernier vendredi
///     🔄 Tous les ans le 15/03               🔄 3 mois après avoir été faite
nonisolated enum Recurrence: Equatable, Sendable {
    enum Unit: String, CaseIterable, Sendable { case day, week, month }

    case daily(every: Int)
    /// `weekdays` : 1 = dimanche … 7 = samedi (Calendar) ; vide = le jour de l'échéance.
    case weekly(every: Int, weekdays: [Int])
    /// `day` : 1…31, ou 0 pour le dernier jour du mois.
    case monthlyDay(every: Int, day: Int)
    /// `ordinal` : 1…4, ou -1 pour le dernier.
    case monthlyWeekday(every: Int, ordinal: Int, weekday: Int)
    case yearly(month: Int, day: Int)
    /// L'échéance suivante part du jour où la tâche a été faite (filtre, sauvegarde…).
    case afterDone(amount: Int, unit: Unit)

    static let marker = "🔄"
    /// Ajoutée à la tâche faite une fois la suivante créée : les autres appareils ne la recréent pas.
    static let spawnedMarker = "↪ Suivante créée"

    static let weekdayNames = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]

    // MARK: - Ligne des notes

    init?(notes: String) {
        guard let line = notes.components(separatedBy: "\n").map(Self.clean).first(where: { $0.hasPrefix(Self.marker) })
        else { return nil }
        self.init(line: line)
    }

    init?(line raw: String) {
        let text = Self.clean(raw).dropFirst(Self.marker.count).trimmingCharacters(in: .whitespaces).lowercased()
        func number(_ pattern: String) -> Int? {
            guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
            return Int(text[r].filter(\.isNumber))
        }
        if text.contains("après avoir été faite") {
            let amount = number(#"^\d+"#) ?? 1
            let unit: Unit = text.contains("mois") ? .month : text.contains("semaine") ? .week : .day
            self = .afterDone(amount: amount, unit: unit)
        } else if text.hasPrefix("tous les ans") {
            guard let r = text.range(of: #"\d{1,2}/\d{1,2}"#, options: .regularExpression) else { return nil }
            let parts = text[r].split(separator: "/").compactMap { Int($0) }
            self = .yearly(month: parts[1], day: parts[0])
        } else if text.contains("mois") {
            let every = number(#"^tous les \d+"#) ?? 1
            if let weekday = Self.weekdayNames.firstIndex(where: { text.hasSuffix($0) }) {
                let ordinal = text.contains("dernier") ? -1 : (number(#"le \d"#) ?? 1)
                self = .monthlyWeekday(every: every, ordinal: ordinal, weekday: weekday + 1)
            } else if text.contains("dernier jour") {
                self = .monthlyDay(every: every, day: 0)
            } else if let day = number(#"le \d{1,2}"#) {
                self = .monthlyDay(every: every, day: day)
            } else {
                return nil
            }
        } else if text.contains("semaine") {
            let every = number(#"^toutes les \d+"#) ?? 1
            let days = Self.weekdayNames.indices.filter { text.contains(Self.weekdayNames[$0]) }.map { $0 + 1 }
            self = .weekly(every: every, weekdays: days)
        } else if text.contains("jour") {
            self = .daily(every: number(#"^tous les \d+"#) ?? 1)
        } else {
            return nil
        }
    }

    var line: String { Self.marker + " " + text }

    /// « Tous les mois le 5 », « Toutes les semaines : lundi, jeudi »…
    var text: String {
        func every(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : many.replacingOccurrences(of: "N", with: "\(n)") }
        switch self {
        case .daily(let n): return every(n, "Tous les jours", "Tous les N jours")
        case .weekly(let n, let days):
            let base = every(n, "Toutes les semaines", "Toutes les N semaines")
            return days.isEmpty ? base : base + " : " + days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { Self.weekdayNames[$0 - 1] }.joined(separator: ", ")
        case .monthlyDay(let n, let day):
            return every(n, "Tous les mois", "Tous les N mois") + (day == 0 ? " le dernier jour" : " le \(day)")
        case .monthlyWeekday(let n, let ordinal, let weekday):
            let rank = ordinal == -1 ? "dernier" : ordinal == 1 ? "1er" : "\(ordinal)e"
            return every(n, "Tous les mois", "Tous les N mois") + " le \(rank) \(Self.weekdayNames[weekday - 1])"
        case .yearly(let month, let day): return String(format: "Tous les ans le %02d/%02d", day, month)
        case .afterDone(let amount, let unit):
            let name = switch unit { case .day: amount > 1 ? "jours" : "jour"; case .week: amount > 1 ? "semaines" : "semaine"; case .month: "mois" }
            return "\(amount) \(name) après avoir été faite"
        }
    }

    /// Les notes avec cette règle à la place de l'ancienne (à la fin), ou sans règle.
    static func notes(_ notes: String, setting recurrence: Recurrence?) -> String {
        var lines = notes.components(separatedBy: "\n").filter { !clean($0).hasPrefix(marker) }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        if let recurrence { lines.append(recurrence.line) }
        return lines.joined(separator: "\n")
    }

    // MARK: - Prochaine échéance

    /// Prochain jour après `due` (règles à date fixe) ou après `done` (« après avoir été faite »),
    /// jamais avant aujourd'hui : une tâche faite en retard ne recrée pas des échéances passées.
    func nextDay(after due: Date, done: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: done)
        if case .afterDone(let amount, let unit) = self {
            let component: Calendar.Component = switch unit { case .day: .day; case .week: .weekOfYear; case .month: .month }
            return calendar.date(byAdding: component, value: amount, to: today)!
        }
        var day = step(from: calendar.startOfDay(for: due), calendar: calendar)
        var guardCount = 0
        while day <= today, guardCount < 1000 {
            day = step(from: day, calendar: calendar)
            guardCount += 1
        }
        return day
    }

    /// Occurrence suivante strictement après `day`.
    private func step(from day: Date, calendar: Calendar) -> Date {
        switch self {
        case .daily(let n):
            return calendar.date(byAdding: .day, value: n, to: day)!
        case .weekly(let n, let days):
            let weekday = calendar.component(.weekday, from: day)
            let wanted = days.isEmpty ? [weekday] : days
            // D'abord un autre jour de la même semaine, sinon le premier jour voulu de la semaine N plus loin.
            for offset in 1...6 {
                let next = calendar.date(byAdding: .day, value: offset, to: day)!
                let w = calendar.component(.weekday, from: next)
                if wanted.contains(w), Self.mondayIndex(w) > Self.mondayIndex(weekday) { return next }
            }
            let startOfWeek = calendar.date(byAdding: .day, value: -Self.mondayIndex(weekday), to: day)!
            let target = calendar.date(byAdding: .weekOfYear, value: n, to: startOfWeek)!
            let first = wanted.map(Self.mondayIndex).min()!
            return calendar.date(byAdding: .day, value: first, to: target)!
        case .monthlyDay(let n, let wantedDay):
            let month = calendar.date(byAdding: .month, value: n, to: calendar.date(from: calendar.dateComponents([.year, .month], from: day))!)!
            let length = calendar.range(of: .day, in: .month, for: month)!.count
            return calendar.date(byAdding: .day, value: (wantedDay == 0 ? length : min(wantedDay, length)) - 1, to: month)!
        case .monthlyWeekday(let n, let ordinal, let weekday):
            let month = calendar.date(byAdding: .month, value: n, to: calendar.date(from: calendar.dateComponents([.year, .month], from: day))!)!
            var c = calendar.dateComponents([.year, .month], from: month)
            c.weekday = weekday
            c.weekdayOrdinal = ordinal
            return calendar.date(from: c) ?? month
        case .yearly(let m, let d):
            let year = calendar.component(.year, from: day)
            let thisYear = calendar.date(from: DateComponents(year: year, month: m, day: d))!
            return thisYear > day ? thisYear : calendar.date(from: DateComponents(year: year + 1, month: m, day: d))!
        case .afterDone:
            return day
        }
    }

    /// Lundi = 0 … dimanche = 6.
    private static func mondayIndex(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    private static func clean(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
    }
}
