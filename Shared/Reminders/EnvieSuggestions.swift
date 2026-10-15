import Foundation

/// Suggestions d'envies au bon moment (Réglages › Relances › Suggestions) : un livre le soir, un album le matin,
/// un film le vendredi. Une par créneau, sans son ; jamais pendant la plage silencieuse.
nonisolated struct EnvieSuggestions: Codable, Equatable, Sendable {
    /// Un créneau par type : l'heure et les jours de la semaine (1 = dimanche … 7 = samedi, comme `Calendar`).
    struct Slot: Codable, Equatable, Sendable {
        var enabled = true
        var minutes: Int
        var weekdays: Set<Int>
    }

    var read = Slot(minutes: 21 * 60 + 30, weekdays: Set(1...7))
    var listen = Slot(minutes: 8 * 60 + 30, weekdays: [2, 3, 4, 5, 6])
    var watch = Slot(minutes: 20 * 60 + 45, weekdays: [6, 7])
    /// Après « Pas maintenant », l'envie n'est plus proposée pendant ce nombre de jours.
    static let skipDays = 7

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        read = (try? c.decodeIfPresent(Slot.self, forKey: .read)) ?? read
        listen = (try? c.decodeIfPresent(Slot.self, forKey: .listen)) ?? listen
        watch = (try? c.decodeIfPresent(Slot.self, forKey: .watch)) ?? watch
    }

    /// Les sorties (« À voir ») ont déjà leurs rappels de période : pas de suggestion.
    static let kinds: [ToSee.Kind] = [.read, .listen, .watch]

    subscript(kind: ToSee.Kind) -> Slot? {
        get {
            switch kind {
            case .read: read
            case .listen: listen
            case .watch: watch
            case .outing: nil
            }
        }
        set {
            guard let newValue else { return }
            switch kind {
            case .read: read = newValue
            case .listen: listen = newValue
            case .watch: watch = newValue
            case .outing: break
            }
        }
    }

    /// « Un moment pour lire ? » : le texte de la notification.
    static func prompt(for kind: ToSee.Kind, at date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let moment = hour < 12 ? "ce matin" : hour < 18 ? "cet après-midi" : "ce soir"
        return switch kind {
        case .read: "Un moment pour lire \(moment) ?"
        case .listen: "À écouter \(moment) ?"
        case .watch: "Envie de regarder ça \(moment) ?"
        case .outing: "À voir ?"
        }
    }
}

/// Ce qui a déjà été proposé, gardé sur l'appareil qui relance : on tourne parmi les envies
/// (la moins récemment proposée d'abord) et on n'en repropose pas une écartée par « Pas maintenant ».
nonisolated struct EnvieHistory: Codable, Equatable, Sendable {
    /// Dernière proposition par envie (identifiant de tâche).
    var lastSuggested: [String: Date] = [:]
    /// « Pas maintenant » : pas avant cette date.
    var skippedUntil: [String: Date] = [:]
    /// Suggestions programmées au dernier calcul : celles passées ont été montrées.
    var planned: [String: Date] = [:]

    private static let key = "envieHistory"

    static func load(from defaults: UserDefaults) -> EnvieHistory {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(EnvieHistory.self, from: $0) } ?? EnvieHistory()
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    /// Les suggestions programmées dont l'heure est passée comptent comme proposées.
    mutating func recordShown(now: Date) {
        for (id, date) in planned where date <= now {
            if (lastSuggested[id] ?? .distantPast) < date { lastSuggested[id] = date }
        }
        planned = planned.filter { $0.value > now }
    }

    mutating func skip(_ id: String, now: Date, calendar: Calendar = .current) {
        skippedUntil[id] = calendar.date(byAdding: .day, value: EnvieSuggestions.skipDays, to: now)
        lastSuggested[id] = now
    }

    /// Oublie les envies qui n'existent plus (faites, supprimées).
    mutating func keepOnly(_ ids: Set<String>, now: Date) {
        lastSuggested = lastSuggested.filter { ids.contains($0.key) }
        skippedUntil = skippedUntil.filter { ids.contains($0.key) && $0.value > now }
    }
}

nonisolated extension ReminderPlanner {
    /// Pour chaque type, chaque jour de créneau d'ici l'horizon : une envie de ce type, en tournant
    /// (jamais proposée, puis la moins récemment proposée). Rien s'il n'y a pas d'envie de ce type.
    func suggestions(tasks: [PlannableTask], history: EnvieHistory, now: Date, horizon: Date) -> [PlannedReminder] {
        var reminders: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)
        for kind in EnvieSuggestions.kinds {
            guard let slot = settings.suggestions[kind], slot.enabled, !slot.weekdays.isEmpty,
                  !settings.isQuiet(minuteOfDay: slot.minutes) else { continue }
            var dates: [Date] = []
            var day = today
            while day <= horizon {
                let fire = calendar.date(bySettingHour: slot.minutes / 60, minute: slot.minutes % 60, second: 0, of: day)!
                if fire > now, fire <= horizon, slot.weekdays.contains(calendar.component(.weekday, from: day)) {
                    dates.append(fire)
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            let candidates = tasks.filter { $0.dueDay == nil && $0.toSee?.kind == kind }
                .sorted { a, b in
                    let la = history.lastSuggested[a.id] ?? .distantPast, lb = history.lastSuggested[b.id] ?? .distantPast
                    return la != lb ? la < lb : a.id < b.id
                }
            var used: [String] = []
            for fire in dates {
                // Disponible ce jour-là (période commencée, pas finie, pas écartée), la moins récemment prise.
                let available = candidates.filter { task in
                    guard let toSee = task.toSee else { return false }
                    if let start = toSee.start, start > fire { return false }
                    if let end = toSee.end, calendar.date(byAdding: .day, value: 1, to: end)! <= fire { return false }
                    if let until = history.skippedUntil[task.id], until > fire { return false }
                    return true
                }
                guard let task = available.min(by: { (used.lastIndex(of: $0.id) ?? -1) < (used.lastIndex(of: $1.id) ?? -1) })
                else { continue }
                used.append(task.id)
                reminders.append(PlannedReminder(
                    id: "\(task.id)|\(ReminderKind.suggestion.rawValue)|\(Int(fire.timeIntervalSince1970))",
                    taskID: task.id, fireDate: fire, kind: .suggestion, title: task.title,
                    body: EnvieSuggestions.prompt(for: kind, at: fire, calendar: calendar)
                        + (task.linkHost.map { " · " + $0 } ?? ""),
                    timeSensitive: false, badge: 0, subtitle: kind.title, hasPlace: task.hasPlace))
            }
        }
        return reminders
    }
}
