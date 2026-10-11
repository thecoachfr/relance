import Foundation

/// Textes d'échéance, identiques dans l'app, les widgets et l'activité en direct.
nonisolated enum DueText {
    /// `due` : heure prévue, ou fin du jour (minuit suivant) pour une tâche sans heure.
    static func isLate(due: Date, now: Date) -> Bool { due < now }

    /// « En retard · depuis hier », « Aujourd'hui à 15 h », « Demain à 9 h 30 », « mer. 14 oct. ».
    static func long(due: Date, hasTime: Bool, now: Date = .now, calendar: Calendar = .current) -> String {
        if isLate(due: due, now: now) { return "En retard · " + since(due: due, hasTime: hasTime, now: now, calendar: calendar) }
        let day = plannedDay(due: due, hasTime: hasTime, calendar: calendar)
        let time = hasTime ? " à " + clock(due, calendar: calendar) : ""
        if calendar.isDate(day, inSameDayAs: now) { return "Aujourd'hui" + time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Demain" + time }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + time
    }

    /// Version courte pour les lignes serrées : « hier », « 21 h », « 3 j », « demain ».
    static func short(due: Date, hasTime: Bool, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = plannedDay(due: due, hasTime: hasTime, calendar: calendar)
        let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day ?? 0
        if isLate(due: due, now: now) {
            switch days {
            case ..<1: return hasTime ? clock(due, calendar: calendar) : "aujourd'hui"
            case 1: return "hier"
            default: return "\(days) j"
            }
        }
        switch days {
        case 0: return hasTime ? clock(due, calendar: calendar) : "aujourd'hui"
        case -1: return "demain"
        default: return day.formatted(.dateTime.weekday(.abbreviated))
        }
    }

    /// « depuis 21 h », « depuis hier », « depuis 3 j ».
    static func since(due: Date, hasTime: Bool, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = plannedDay(due: due, hasTime: hasTime, calendar: calendar)
        let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return hasTime ? "depuis " + clock(due, calendar: calendar) : "aujourd'hui"
        case 1: return "depuis hier"
        default: return "depuis \(days) j"
        }
    }

    /// « 15 h », « 9 h 30 ».
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return ReminderPlanner.formatTime((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Jour prévu : pour une tâche sans heure, `due` est le minuit suivant, donc la veille.
    private static func plannedDay(due: Date, hasTime: Bool, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: due)
        if hasTime { return start }
        return calendar.date(byAdding: .day, value: -1, to: start) ?? start
    }
}
