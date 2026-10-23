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
    /// La tâche a une adresse (ligne 📍) : bouton « Itinéraire » plutôt que « Dans 1 h » avant l'heure.
    var hasPlace = false
    /// « À voir » (sans échéance) : relances seulement autour de sa période.
    var toSee: ToSee?
    /// Site du premier lien des notes (« youtube.com ») : montré dans une suggestion d'envie.
    var linkHost: String?
    /// Rattachée à mes lieux (liste de courses et ses magasins) : le passage devant le magasin tient lieu
    /// d'heure, pas de « À quelle heure ? ».
    var atMyPlaces = false
    /// Première image jointe (P9-K) : montrée dans la notification de l'heure prévue.
    var imageID: String?
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
    var toSee = ToSeeSettings()
    /// Suggestions d'envies (à lire, à écouter, à regarder) à heure fixe.
    var suggestions = EnvieSuggestions()
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

nonisolated enum ReminderKind: String, Sendable, Equatable, Codable {
    case departure, advance, due, followUp, evening, askTime, overdue, snoozed, digest
    /// « À voir » : ouverture, quelques semaines avant la fin, dernier week-end.
    case toSeeOpening, toSeeEnding, toSeeLastWeekend
    /// Une envie proposée au bon moment (« Un moment pour lire ce soir ? »).
    case suggestion
    /// Sortie réservée (P9-L1) : une semaine avant, la veille au soir, 2 h avant (avec le billet).
    case eventWeek, eventEve, eventSoon
}

/// Relances des « À voir » : peu nombreuses, autour de la période (Réglages › Relances › À voir).
nonisolated struct ToSeeSettings: Codable, Equatable, Sendable {
    var atOpening = true
    /// Semaines avant la fin ; `nil` = pas de rappel.
    var weeksBeforeEnd: Int? = 3
    var lastWeekend = true
    /// Heure des rappels (minutes depuis minuit).
    var time = 10 * 60
    /// Types d'envie dont le rappel à l'approche est activé sans rien faire (P9-A4) : les spots photo,
    /// où l'on passe sans y penser. Chaque envie peut ensuite l'activer ou le couper.
    var nearbyKinds: [String] = [ToSee.Kind.photoSpot.rawValue]

    init() {}

    func nearbyByDefault(_ kind: ToSee.Kind?) -> Bool { kind.map { nearbyKinds.contains($0.rawValue) } ?? false }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        atOpening = try c.decodeIfPresent(Bool.self, forKey: .atOpening) ?? atOpening
        weeksBeforeEnd = try c.decodeIfPresent(Int.self, forKey: .weeksBeforeEnd)
        lastWeekend = try c.decodeIfPresent(Bool.self, forKey: .lastWeekend) ?? lastWeekend
        time = try c.decodeIfPresent(Int.self, forKey: .time) ?? time
        nearbyKinds = try c.decodeIfPresent([String].self, forKey: .nearbyKinds) ?? nearbyKinds
    }
}

nonisolated struct PlannedReminder: Sendable, Equatable, Codable {
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
    /// La tâche a une adresse (boutons de la notification).
    var hasPlace = false
    /// Image jointe à montrer dans la notification (pièce de la tâche, P9-K).
    var imageID: String?
}

/// Calcule toutes les relances à programmer. Fonction pure : mêmes tâches + même instant = même plan.
nonisolated struct ReminderPlanner: Sendable {
    var calendar: Calendar
    var settings = ReminderSettings()
    /// Suggestions déjà faites sur cet appareil (rotation, « Pas maintenant »).
    var history = EnvieHistory()

    func plan(tasks: [PlannableTask], inboxCount: Int, now: Date) -> [PlannedReminder] {
        let horizon = calendar.date(byAdding: .day, value: settings.horizonDays, to: now)!
        var reminders: [PlannedReminder] = []

        for task in tasks {
            if task.toSee?.kind.isDated == true {
                reminders += eventReminders(task, now: now, horizon: horizon)
                continue
            }
            if let toSee = task.toSee, task.dueDay == nil {
                reminders += toSeeReminders(task, toSee, now: now, horizon: horizon)
                continue
            }
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
                    subtitle: task.priority == .urgent ? TaskPriority.urgent.rawValue : "",
                    hasPlace: task.hasPlace,
                    imageID: [.due, .advance, .departure].contains(kind) ? task.imageID : nil))
            }
        }

        reminders += folding(into: digests(tasks: tasks, inboxCount: inboxCount, now: now, horizon: horizon), &reminders)
        reminders += suggestions(tasks: tasks, history: history, now: now, horizon: horizon)

        reminders.sort { $0.fireDate < $1.fireDate }
        // iOS garde au plus 64 notifications : l'heure prévue, les rappels « avant », les reports choisis
        // et les résumés passent d'abord ; les relances (souvent répétées) remplissent la place qui reste.
        // Le plan est recalculé à chaque ouverture et chaque synchro, la suite sera programmée plus tard.
        if reminders.count > settings.maxRequests {
            let essential: Set<ReminderKind> = [.departure, .advance, .due, .snoozed, .digest, .eventEve, .eventSoon]
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
        var profile = task.reminders?.applied(to: settings[task.priority]) ?? settings[task.priority]
        if task.atMyPlaces { profile.askTime = false }
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

    /// Relances du matin (report « demain matin », moment du matin, retard) qui tombent avec le résumé « Ta journée » :
    /// retirées et résumées dedans (« · urgent : Faire la facture, Répondre à Didier »), une seule notification au
    /// réveil (demande d'Alexandre, 18/10). L'heure prévue, le rappel « avant », le départ et « À quelle heure ? »
    /// restent à part.
    private func folding(into digests: [PlannedReminder], _ reminders: inout [PlannedReminder]) -> [PlannedReminder] {
        // « À quelle heure ? » reste à part : c'est une question, avec ses boutons pour choisir l'heure.
        let foldable: Set<ReminderKind> = [.snoozed, .evening, .overdue, .followUp]
        var digests = digests
        for i in digests.indices where digests[i].id.hasPrefix("digest|") && !digests[i].id.hasPrefix("digest|evening") {
            let fire = digests[i].fireDate
            let folded = reminders.filter {
                $0.taskID != nil && foldable.contains($0.kind) && abs($0.fireDate.timeIntervalSince(fire)) <= Self.foldWindow
            }
            guard !folded.isEmpty else { continue }
            let ids = Set(folded.map(\.id))
            reminders.removeAll { ids.contains($0.id) }
            var urgent: [String] = []
            for r in folded where r.subtitle == TaskPriority.urgent.rawValue && !urgent.contains(r.title) { urgent.append(r.title) }
            if !urgent.isEmpty {
                digests[i].body += " · urgent : " + urgent.prefix(2).joined(separator: ", ") + (urgent.count > 2 ? "…" : "")
            }
            digests[i].timeSensitive = folded.contains(where: \.timeSensitive)
        }
        return digests
    }

    /// Écart toléré entre une relance et le résumé du matin pour la fondre dedans.
    static let foldWindow: TimeInterval = 15 * 60

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

    /// Ouverture (si elle est à venir), quelques semaines avant la fin, et le samedi du dernier week-end.
    private func toSeeReminders(_ task: PlannableTask, _ toSee: ToSee, now: Date, horizon: Date) -> [PlannedReminder] {
        let s = settings.toSee
        var events: [(Date, ReminderKind, String)] = []
        if s.atOpening, let start = toSee.start {
            events.append((at(start, s.time), .toSeeOpening, (toSee.kind == .outing ? "C'est ouvert" : "C'est disponible") + (toSee.end.map { " jusqu'au " + $0.formatted(.dateTime.day().month(.wide)) } ?? "") + "."))
        }
        if let end = toSee.end {
            if let weeks = s.weeksBeforeEnd, let day = calendar.date(byAdding: .day, value: -7 * weeks, to: end) {
                events.append((at(day, s.time), .toSeeEnding, "Plus que \(weeks) semaine\(weeks > 1 ? "s" : "") : jusqu'au " + end.formatted(.dateTime.day().month(.wide)) + "."))
            }
            // Samedi du dernier week-end (ou la veille si la fin tombe un samedi : on garde le samedi lui-même).
            let weekday = calendar.component(.weekday, from: end)   // 1 = dimanche, 7 = samedi
            let back = weekday == 7 ? 0 : weekday == 1 ? 1 : weekday
            if s.lastWeekend, let saturday = calendar.date(byAdding: .day, value: -back, to: end) {
                events.append((at(saturday, s.time), .toSeeLastWeekend, "Dernier week-end : jusqu'au " + end.formatted(.dateTime.weekday(.wide).day().month(.wide)) + "."))
            }
        }
        return events.filter { $0.0 > now && $0.0 <= horizon && !isMuted($0.0, $0.1) }.map { date, kind, body in
            PlannedReminder(id: "\(task.id)|\(kind.rawValue)|\(Int(date.timeIntervalSince1970))", taskID: task.id,
                            fireDate: date, kind: kind, title: task.title, body: body,
                            timeSensitive: false, badge: 0, subtitle: toSee.kind.title, hasPlace: task.hasPlace)
        }
    }

    /// Sortie réservée (P9-L1) : une semaine avant (heure des envies), la veille au soir, puis 2 h avant avec la
    /// photo du billet s'il y en a une (sans heure : le matin du jour). Ni relance ni retard : c'est un rendez-vous.
    private func eventReminders(_ task: PlannableTask, now: Date, horizon: Date) -> [PlannedReminder] {
        guard let dueDay = task.dueDay, let dayStart = calendar.date(from: dueDay) else { return [] }
        let time = task.dueMinutes.map { " à " + Self.formatTime($0) } ?? ""
        let day = dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide))
        var events: [(Date, ReminderKind, String)] = []
        if let week = calendar.date(byAdding: .day, value: -7, to: dayStart) {
            events.append((at(week, settings.toSee.time), .eventWeek, "Dans une semaine : \(day)\(time)."))
        }
        if let eve = calendar.date(byAdding: .day, value: -1, to: dayStart) {
            events.append((at(eve, settings.evening), .eventEve, "Demain\(time)."))
        }
        if let minutes = task.dueMinutes {
            events.append((at(dayStart, minutes - 120), .eventSoon, "Dans 2 h\(time) · ton billet est dans la fiche."))
        } else {
            events.append((at(dayStart, settings.morning), .eventSoon, "Aujourd'hui · ton billet est dans la fiche."))
        }
        return events.filter { $0.0 > now && $0.0 <= horizon && !isMuted($0.0, $0.1) }.map { date, kind, body in
            PlannedReminder(id: "\(task.id)|\(kind.rawValue)|\(Int(date.timeIntervalSince1970))", taskID: task.id,
                            fireDate: date, kind: kind, title: task.title, body: body,
                            timeSensitive: kind == .eventSoon, badge: 0, subtitle: ToSee.Kind.event.title,
                            hasPlace: task.hasPlace, imageID: kind == .eventSoon ? task.imageID : nil)
        }
    }

    /// La plage silencieuse coupe tout, sauf l'échéance elle-même et un report choisi explicitement.
    private func isMuted(_ date: Date, _ kind: ReminderKind) -> Bool {
        // L'heure prévue, le départ et un report choisi passent toujours : rater un départ, c'est rater le rendez-vous.
        guard kind != .due, kind != .snoozed, kind != .departure else { return false }
        return settings.isQuiet(minuteOfDay: minuteOfDay(date))
    }

    func isOverdue(_ task: PlannableTask, at date: Date) -> Bool {
        guard task.toSee?.kind.isDated != true, let d = task.dueDay, let dayStart = calendar.date(from: d) else { return false }
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
        case .digest, .toSeeOpening, .toSeeEnding, .toSeeLastWeekend, .suggestion, .eventWeek, .eventEve, .eventSoon: return ""
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
