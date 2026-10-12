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
    var priority: TaskPriority = .normal
    /// Relances propres à la tâche, par-dessus le profil de sa priorité.
    var reminders: ReminderOverride?
    /// Temps de trajet jusqu'à l'adresse de la tâche (Plans), pour « Pars maintenant ».
    var travelMinutes: Int?
}

nonisolated struct ReminderSettings: Sendable, Equatable {
    var morning = 7 * 60 + 30
    var evening = 20 * 60
    var quietStart = 22 * 60
    var quietEnd = 7 * 60 + 30
    var midday = 12 * 60
    /// Résumé du soir : les tâches du lendemain. Après la relance de 20 h, pour ne pas sonner en même temps.
    var eveningDigest = true
    var eveningDigestTime = 21 * 60
    /// Week-end : seules l'heure prévue, les reports choisis et les tâches urgentes relancent.
    var calmWeekends = false
    var urgent = ReminderProfile.defaults(for: .urgent)
    var normal = ReminderProfile.defaults(for: .normal)
    var low = ReminderProfile.defaults(for: .low)
    var departure = DepartureSettings()
    /// Nombre de jours de relances programmés à l'avance.
    var horizonDays = 7
    /// iOS garde au plus 64 notifications locales en attente par app.
    var maxRequests = 60

    subscript(priority: TaskPriority) -> ReminderProfile {
        get {
            switch priority {
            case .urgent: urgent
            case .normal: normal
            case .low: low
            }
        }
        set {
            switch priority {
            case .urgent: urgent = newValue
            case .normal: normal = newValue
            case .low: low = newValue
            }
        }
    }

    func minutes(of slot: ReminderProfile.Slot) -> Int {
        switch slot {
        case .morning: morning
        case .midday: midday
        case .evening: evening
        }
    }

    func isQuiet(minuteOfDay m: Int) -> Bool {
        quietStart > quietEnd ? (m >= quietStart || m < quietEnd) : (m >= quietStart && m < quietEnd)
    }
}

nonisolated enum ReminderKind: String, Sendable, Equatable {
    case departure, advance, due, followUp, evening, askTime, overdue, snoozed, digest
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
    /// « Urgente » sous le titre ; vide sinon.
    var subtitle = ""
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

            for (date, kind) in events where date > now && date <= horizon && !isMuted(date, kind)
                && !isCalmed(task, date, kind) {
                reminders.append(PlannedReminder(
                    id: "\(task.id)|\(kind.rawValue)|\(Int(date.timeIntervalSince1970))",
                    taskID: task.id,
                    fireDate: date,
                    kind: kind,
                    title: task.title,
                    body: body(for: task, kind: kind, at: date),
                    timeSensitive: isTimeSensitive(task.priority, kind),
                    badge: 0,
                    subtitle: task.priority == .urgent ? TaskPriority.urgent.rawValue : ""))
            }
        }

        reminders += digests(tasks: tasks, inboxCount: inboxCount, now: now, horizon: horizon)

        reminders.sort { $0.fireDate < $1.fireDate }
        // iOS garde au plus 64 notifications : l'heure prévue, les rappels « avant », les reports choisis
        // et les résumés passent d'abord ; les relances (souvent répétées) remplissent la place qui reste.
        // Le plan est recalculé à chaque ouverture et chaque synchro, la suite sera programmée plus tard.
        if reminders.count > settings.maxRequests {
            let essential: Set<ReminderKind> = [.departure, .advance, .due, .snoozed, .digest]
            let kept = reminders.filter { essential.contains($0.kind) }.prefix(settings.maxRequests)
            let rest = reminders.filter { !essential.contains($0.kind) }.prefix(settings.maxRequests - kept.count)
            reminders = (Array(kept) + rest).sorted { $0.fireDate < $1.fireDate }
        }
        for i in reminders.indices {
            reminders[i].badge = tasks.filter { isOverdue($0, at: reminders[i].fireDate) }.count
        }
        return reminders
    }

    // MARK: - Règles

    /// Tout vient du profil de la priorité (`ReminderProfile`) :
    /// avant l'heure, à l'heure, relance(s) après, puis les moments de la journée (matin, midi, soir)
    /// le jour prévu et chaque jour de retard.
    private func events(for task: PlannableTask, dayStart: Date, horizon: Date) -> [(date: Date, kind: ReminderKind)] {
        let profile = task.reminders?.applied(to: settings[task.priority]) ?? settings[task.priority]
        var events: [(Date, ReminderKind)] = []
        let slots = ReminderProfile.Slot.allCases.filter { profile.slots.contains($0) }
            .map { at(dayStart, settings.minutes(of: $0)) }

        if let minutes = task.dueMinutes {
            let due = at(dayStart, minutes)
            if let advance = profile.advanceMinutes { events.append((due.addingTimeInterval(-Double(advance) * 60), .advance)) }
            events.append((due, .due))
            if let travel = task.travelMinutes, settings.departure.enabled {
                let leave = due.addingTimeInterval(-Double(travel + settings.departure.marginMinutes) * 60)
                events.append((leave, .departure))
            }
            var last = due
            if let interval = profile.followUpMinutes.map({ TimeInterval($0) * 60 }) {
                // Jusqu'à minuit si « jusqu'à ce que ce soit fait » ; la plage silencieuse coupe la nuit (`isMuted`).
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                var next = due.addingTimeInterval(interval)
                repeat {
                    guard next < endOfDay else { break }
                    events.append((next, .followUp))
                    last = next
                    next = next.addingTimeInterval(interval)
                } while profile.followUpRepeats
            }
            // Moments de la journée après la dernière relance (ex. 20 h après « à l'heure, +1 h »).
            events += slots.filter { $0 > last }.map { ($0, .evening) }
        } else {
            let morning = at(dayStart, settings.morning)
            if profile.askTime { events.append((morning, .askTime)) }
            events += slots.filter { !profile.askTime || $0 != morning }.map { ($0, .evening) }
        }

        var day = 1
        while let next = calendar.date(byAdding: .day, value: day, to: dayStart), next <= horizon {
            for slot in ReminderProfile.Slot.allCases where profile.slots.contains(slot) {
                events.append((at(next, settings.minutes(of: slot)), .overdue))
            }
            day += 1
        }
        return events
    }

    private func isTimeSensitive(_ priority: TaskPriority, _ kind: ReminderKind) -> Bool {
        if kind == .departure { return true }
        return switch settings[priority].breakthrough {
        case .always: kind != .digest
        case .important: [.advance, .due, .evening, .overdue, .snoozed].contains(kind)
        case .never: false
        }
    }

    /// Week-end calme : l'heure prévue et les reports choisis passent toujours, les urgentes aussi.
    private func isCalmed(_ task: PlannableTask, _ date: Date, _ kind: ReminderKind) -> Bool {
        settings.calmWeekends && task.priority != .urgent && kind != .due && kind != .snoozed && kind != .departure
            && calendar.isDateInWeekend(date)
    }

    private func digests(tasks: [PlannableTask], inboxCount: Int, now: Date, horizon: Date) -> [PlannedReminder] {
        var digests: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)

        for offset in 0...settings.horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // Le soir d'abord : il a lieu même quand le résumé du matin de ce jour est passé ou vide.
            if settings.eveningDigest, let evening = eveningDigest(tasks: tasks, day: day, now: now, horizon: horizon) {
                digests.append(evening)
            }
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

    /// « Demain » : « 3 tâches, dont 1 urgente · la première à 9 h · 1 encore en retard ». Rien si demain est vide
    /// et que rien n'est en retard.
    private func eveningDigest(tasks: [PlannableTask], day: Date, now: Date, horizon: Date) -> PlannedReminder? {
        let fire = at(day, settings.eveningDigestTime)
        guard fire > now, fire <= horizon, let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        let planned = tasks.filter { task in
            guard let d = task.dueDay, let start = calendar.date(from: d) else { return false }
            return calendar.isDate(start, inSameDayAs: tomorrow)
        }
        let overdue = tasks.filter { isOverdue($0, at: fire) }.count
        guard !planned.isEmpty || overdue > 0 else { return nil }

        var parts: [String] = []
        if planned.isEmpty {
            parts.append("Rien de prévu")
        } else {
            let urgent = planned.filter { $0.priority == .urgent }.count
            var count = planned.count == 1 ? "1 tâche" : "\(planned.count) tâches"
            if urgent > 0 { count += planned.count == 1 ? ", urgente" : ", dont \(urgent) urgente" + (urgent > 1 ? "s" : "") }
            parts.append(count)
            if let first = planned.compactMap(\.dueMinutes).min() {
                parts.append((planned.count == 1 ? "à " : "la première à ") + Self.formatTime(first))
            }
        }
        if overdue > 0 { parts.append("\(overdue) encore en retard") }

        return PlannedReminder(
            id: "digest|evening|\(Int(fire.timeIntervalSince1970))",
            taskID: nil,
            fireDate: fire,
            kind: .digest,
            title: "Demain",
            body: parts.joined(separator: " · "),
            timeSensitive: false,
            badge: 0)
    }

    /// La plage silencieuse coupe tout, sauf l'échéance elle-même et un report choisi explicitement.
    private func isMuted(_ date: Date, _ kind: ReminderKind) -> Bool {
        // L'heure prévue, le départ et un report choisi passent toujours : rater un départ, c'est rater le rendez-vous.
        guard kind != .due, kind != .snoozed, kind != .departure else { return false }
        return settings.isQuiet(minuteOfDay: minuteOfDay(date))
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
        case .departure:
            let travel = task.travelMinutes.map { " · \($0) min \(settings.departure.mode.phrase)" } ?? ""
            return "Pars maintenant\(travel) · prévu\(time)."
        case .advance: return advanceText(task, at: date) + " · prévu\(time)."
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

    /// « Dans 15 min », « Dans 1 h », « Demain ».
    private func advanceText(_ task: PlannableTask, at date: Date) -> String {
        guard let d = task.dueDay, let start = calendar.date(from: d), let m = task.dueMinutes else { return "Bientôt" }
        let minutes = Int(at(start, m).timeIntervalSince(date) / 60)
        switch minutes {
        case ..<60: return "Dans \(minutes) min"
        case ..<(24 * 60): return "Dans \(minutes / 60) h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)")
        default: return calendar.isDate(at(start, m), inSameDayAs: date.addingTimeInterval(86400)) ? "Demain" : "Bientôt"
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
