import Foundation

/// Tâche telle que le planificateur la voit : rien d'autre que ce qui décide des relances.
nonisolated struct PlannableTask: Sendable, Equatable {
    var id: String
    var title: String
    /// Jour d'échéance (année, mois, jour). `nil` = tâche sans date, à trier.
    var dueDay: DateComponents?
    /// Heure d'échéance en minutes depuis minuit. `nil` = date seule (cas des dictées Google Home).
    var dueMinutes: Int?
    var snoozedUntil: Date?
}

nonisolated struct ReminderSettings: Sendable, Equatable {
    var morning = 7 * 60 + 30
    var evening = 20 * 60
    var quietStart = 22 * 60
    var quietEnd = 7 * 60 + 30
    var followUpDelay: TimeInterval = 3600
    /// Nombre de jours de relances programmés à l'avance.
    var horizonDays = 7
    /// iOS garde au plus 64 notifications locales en attente par app.
    var maxRequests = 60
}

nonisolated enum ReminderKind: String, Sendable, Equatable {
    case due, followUp, evening, askTime, overdue, snoozed, digest
}

nonisolated struct PlannedReminder: Sendable, Equatable {
    var id: String
    /// `nil` pour le résumé du matin.
    var taskID: String?
    var fireDate: Date
    var kind: ReminderKind
    var title: String
    var body: String
    var timeSensitive: Bool
    /// Nombre de tâches en retard au moment où la notification s'affiche.
    var badge: Int
}

/// Calcule toutes les relances à programmer. Fonction pure : mêmes tâches + même instant = même plan.
nonisolated struct ReminderPlanner: Sendable {
    var calendar: Calendar
    var settings = ReminderSettings()

    func plan(tasks: [PlannableTask], inboxCount: Int, now: Date) -> [PlannedReminder] {
        let horizon = calendar.date(byAdding: .day, value: settings.horizonDays, to: now)!
        var reminders: [PlannedReminder] = []

        for task in tasks {
            guard let dueDay = task.dueDay, let dayStart = calendar.date(from: dueDay) else { continue }
            var events = events(for: task, dayStart: dayStart, horizon: horizon)

            if let snooze = task.snoozedUntil, snooze > now {
                events.removeAll { $0.date < snooze }
                events.append((snooze, .snoozed))
            }

            for (date, kind) in events where date > now && date <= horizon && !isMuted(date, kind) {
                reminders.append(PlannedReminder(
                    id: "\(task.id)|\(kind.rawValue)|\(Int(date.timeIntervalSince1970))",
                    taskID: task.id,
                    fireDate: date,
                    kind: kind,
                    title: task.title,
                    body: body(for: task, kind: kind, at: date),
                    timeSensitive: [.due, .evening, .overdue, .snoozed].contains(kind),
                    badge: 0))
            }
        }

        reminders += digests(tasks: tasks, inboxCount: inboxCount, now: now, horizon: horizon)

        reminders.sort { $0.fireDate < $1.fireDate }
        reminders = Array(reminders.prefix(settings.maxRequests))
        for i in reminders.indices {
            reminders[i].badge = tasks.filter { isOverdue($0, at: reminders[i].fireDate) }.count
        }
        return reminders
    }

    // MARK: - Règles

    private func events(for task: PlannableTask, dayStart: Date, horizon: Date) -> [(date: Date, kind: ReminderKind)] {
        var events: [(Date, ReminderKind)] = []
        let evening = at(dayStart, settings.evening)

        if let minutes = task.dueMinutes {
            let due = at(dayStart, minutes)
            let followUp = due.addingTimeInterval(settings.followUpDelay)
            events += [(due, .due), (followUp, .followUp)]
            if evening > followUp { events.append((evening, .evening)) }
        } else {
            events += [(at(dayStart, settings.morning), .askTime), (evening, .evening)]
        }

        var day = 1
        while let next = calendar.date(byAdding: .day, value: day, to: dayStart), next <= horizon {
            events.append((at(next, settings.evening), .overdue))
            day += 1
        }
        return events
    }

    private func digests(tasks: [PlannableTask], inboxCount: Int, now: Date, horizon: Date) -> [PlannedReminder] {
        var digests: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)

        for offset in 0...settings.horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let fire = at(day, settings.morning)
            guard fire > now, fire <= horizon else { continue }

            let overdue = tasks.filter { isOverdue($0, at: fire) }.count
            let dueToday = tasks.filter { task in
                guard let d = task.dueDay, let start = calendar.date(from: d) else { return false }
                return calendar.isDate(start, inSameDayAs: day) && !isOverdue(task, at: fire)
            }.count
            guard overdue + dueToday + inboxCount > 0 else { continue }

            var parts: [String] = []
            if overdue > 0 { parts.append("\(overdue) en retard") }
            if dueToday > 0 { parts.append("\(dueToday) aujourd'hui") }
            if inboxCount > 0 { parts.append("\(inboxCount) à trier") }

            digests.append(PlannedReminder(
                id: "digest|\(Int(fire.timeIntervalSince1970))",
                taskID: nil,
                fireDate: fire,
                kind: .digest,
                title: "Ta journée",
                body: parts.joined(separator: " · "),
                timeSensitive: false,
                badge: 0))
        }
        return digests
    }

    /// La plage silencieuse coupe tout, sauf l'échéance elle-même et un report choisi explicitement.
    private func isMuted(_ date: Date, _ kind: ReminderKind) -> Bool {
        guard kind != .due, kind != .snoozed else { return false }
        let m = minuteOfDay(date)
        return settings.quietStart > settings.quietEnd
            ? (m >= settings.quietStart || m < settings.quietEnd)
            : (m >= settings.quietStart && m < settings.quietEnd)
    }

    func isOverdue(_ task: PlannableTask, at date: Date) -> Bool {
        guard let d = task.dueDay, let dayStart = calendar.date(from: d) else { return false }
        if let minutes = task.dueMinutes { return at(dayStart, minutes) < date }
        return calendar.date(byAdding: .day, value: 1, to: dayStart)! <= date
    }

    // MARK: - Textes

    private func body(for task: PlannableTask, kind: ReminderKind, at date: Date) -> String {
        let time = task.dueMinutes.map { " à " + Self.formatTime($0) } ?? ""
        switch kind {
        case .due: return "C'est l'heure · prévu\(time)."
        case .followUp: return "Prévu\(time) · toujours pas fait."
        case .evening: return "Prévu aujourd'hui\(time) · pas encore fait."
        case .askTime: return "Prévu aujourd'hui. À quelle heure ?"
        case .overdue, .snoozed:
            if isOverdue(task, at: date) { return lateText(task, at: date) + "." }
            return "Reporté · prévu\(time)."
        case .digest: return ""
        }
    }

    private func lateText(_ task: PlannableTask, at date: Date) -> String {
        guard let d = task.dueDay, let start = calendar.date(from: d) else { return "En retard" }
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return "En retard"
        case 1: return "En retard depuis hier"
        default: return "En retard depuis \(days) jours"
        }
    }

    static func formatTime(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : String(format: "%d h %02d", h, m)
    }

    // MARK: - Outils

    private func at(_ dayStart: Date, _ minutes: Int) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart)!
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
