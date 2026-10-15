import Foundation

/// Comment insister pour une priorité donnée. Modifiable dans Réglages › Relances ;
/// les valeurs d'origine reproduisent le comportement décrit dans SUIVI.md.
nonisolated struct ReminderProfile: Codable, Equatable, Sendable {
    /// Moments de la journée où l'on relance une tâche sans heure (le jour prévu) ou en retard (les jours suivants).
    enum Slot: String, Codable, CaseIterable, Sendable { case morning, midday, evening }

    /// Ce qui passe le mode Concentration (notification « urgente » d'iOS).
    enum Breakthrough: String, Codable, CaseIterable, Sendable {
        /// Toutes les relances.
        case always
        /// L'heure prévue, la relance du soir, le retard et les reports choisis.
        case important
        case never
    }

    enum LiveActivity: String, Codable, CaseIterable, Sendable {
        /// Dès le jour prévu, en tête.
        case always
        /// Deux heures avant l'échéance, ou en retard.
        case upcoming
        case never
    }

    /// Minutes avant l'heure prévue (tâches avec heure) ; `nil` = pas de rappel avant.
    var advanceMinutes: Int?
    /// Minutes entre l'échéance et la relance suivante ; `nil` = pas de relance après l'heure.
    var followUpMinutes: Int?
    /// Relancer à cet intervalle jusqu'à minuit (sinon une seule fois).
    var followUpRepeats: Bool
    var slots: Set<Slot>
    /// Tâche sans heure : « À quelle heure ? » le matin du jour prévu, et dès son arrivée de Google.
    var askTime: Bool
    var breakthrough: Breakthrough
    var liveActivity: LiveActivity

    static func defaults(for priority: TaskPriority) -> ReminderProfile {
        switch priority {
        case .urgent:
            ReminderProfile(advanceMinutes: nil, followUpMinutes: 30, followUpRepeats: true,
                            slots: [.morning, .midday, .evening], askTime: true,
                            // 2 h avant, comme les normales : toute la journée, c'était trop envahissant (13/10).
                            breakthrough: .always, liveActivity: .upcoming)
        case .normal:
            ReminderProfile(advanceMinutes: nil, followUpMinutes: 60, followUpRepeats: false,
                            slots: [.evening], askTime: true,
                            breakthrough: .important, liveActivity: .upcoming)
        case .low:
            ReminderProfile(advanceMinutes: nil, followUpMinutes: nil, followUpRepeats: false,
                            slots: [], askTime: false,
                            breakthrough: .never, liveActivity: .never)
        }
    }
}

/// « Pars maintenant » : prévenir quand il faut partir pour arriver à l'heure à l'adresse de la tâche (ligne 📍).
nonisolated struct DepartureSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case transit, car, walking

        var label: String {
            switch self {
            case .transit: "Transports en commun"
            case .car: "Voiture"
            case .walking: "À pied"
            }
        }

        /// « 18 min en transports ».
        var phrase: String {
            switch self {
            case .transit: "en transports"
            case .car: "en voiture"
            case .walking: "à pied"
            }
        }

        /// Paramètre « dirflg » de Plans.
        var mapsFlag: String {
            switch self {
            case .transit: "r"
            case .car: "d"
            case .walking: "w"
            }
        }
    }

    var enabled = true
    var mode = Mode.transit
    var marginMinutes = 5
    /// Adresse de départ (domicile). Vide = fonction inactive. Reste sur l'appareil.
    var origin = ""
}

extension ReminderSettings: Codable {
    private enum Keys: String, CodingKey {
        case morning, evening, midday, quietStart, quietEnd, calmWeekends, urgent, normal, low, departure
        case eveningDigest, eveningDigestTime, version, toSee, suggestions
    }

    /// Chaque champ est facultatif : un réglage ajouté plus tard prend sa valeur d'origine.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: Keys.self)
        morning = try c.decodeIfPresent(Int.self, forKey: .morning) ?? morning
        evening = try c.decodeIfPresent(Int.self, forKey: .evening) ?? evening
        midday = try c.decodeIfPresent(Int.self, forKey: .midday) ?? midday
        quietStart = try c.decodeIfPresent(Int.self, forKey: .quietStart) ?? quietStart
        quietEnd = try c.decodeIfPresent(Int.self, forKey: .quietEnd) ?? quietEnd
        calmWeekends = try c.decodeIfPresent(Bool.self, forKey: .calmWeekends) ?? calmWeekends
        urgent = (try? c.decodeIfPresent(ReminderProfile.self, forKey: .urgent)) ?? urgent
        normal = (try? c.decodeIfPresent(ReminderProfile.self, forKey: .normal)) ?? normal
        low = (try? c.decodeIfPresent(ReminderProfile.self, forKey: .low)) ?? low
        departure = (try? c.decodeIfPresent(DepartureSettings.self, forKey: .departure)) ?? departure
        eveningDigest = try c.decodeIfPresent(Bool.self, forKey: .eveningDigest) ?? eveningDigest
        eveningDigestTime = try c.decodeIfPresent(Int.self, forKey: .eveningDigestTime) ?? eveningDigestTime
        toSee = (try? c.decodeIfPresent(ToSeeSettings.self, forKey: .toSee)) ?? toSee
        suggestions = (try? c.decodeIfPresent(EnvieSuggestions.self, forKey: .suggestions)) ?? suggestions
        // v2 (13/10) : les urgentes n'occupent plus l'écran verrouillé toute la journée, mais 2 h avant.
        // On ne change que l'ancienne valeur d'origine ; un choix fait depuis reste tel quel.
        if (try c.decodeIfPresent(Int.self, forKey: .version) ?? 1) < 2, urgent.liveActivity == .always {
            urgent.liveActivity = .upcoming
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(morning, forKey: .morning)
        try c.encode(evening, forKey: .evening)
        try c.encode(midday, forKey: .midday)
        try c.encode(quietStart, forKey: .quietStart)
        try c.encode(quietEnd, forKey: .quietEnd)
        try c.encode(calmWeekends, forKey: .calmWeekends)
        try c.encode(urgent, forKey: .urgent)
        try c.encode(normal, forKey: .normal)
        try c.encode(low, forKey: .low)
        try c.encode(departure, forKey: .departure)
        try c.encode(eveningDigest, forKey: .eveningDigest)
        try c.encode(eveningDigestTime, forKey: .eveningDigestTime)
        try c.encode(2, forKey: .version)
        try c.encode(toSee, forKey: .toSee)
        try c.encode(suggestions, forKey: .suggestions)
    }

    private static let key = "reminderSettings"

    /// Réglages de cet appareil (seul l'iPhone relance par défaut).
    static func load(from defaults: UserDefaults) -> ReminderSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReminderSettings.self, from: $0) } ?? ReminderSettings()
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

nonisolated extension ReminderOverride {
    func applied(to profile: ReminderProfile) -> ReminderProfile {
        var p = profile
        switch advance {
        case .off: p.advanceMinutes = nil
        case .minutes(let m): p.advanceMinutes = m
        case nil: break
        }
        switch followUp {
        case .off: p.followUpMinutes = nil
        case .once(let m): p.followUpMinutes = m; p.followUpRepeats = false
        case .every(let m): p.followUpMinutes = m; p.followUpRepeats = true
        case nil: break
        }
        return p
    }
}
