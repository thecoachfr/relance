import Foundation

/// Tâche telle que l'iPhone l'envoie à la montre (la montre n'a pas accès à Google).
nonisolated struct WatchTask: Codable, Hashable, Identifiable, Sendable {
    /// Identifiant Google de la tâche (ou identifiant local tant qu'elle n'est pas encore chez Google).
    var id: String
    var title: String
    /// Heure prévue, ou fin du jour pour une tâche sans heure ; `nil` = sans date.
    var due: Date?
    var hasTime: Bool
    var snoozedUntil: Date?
    /// `nil` = Normale (et listes envoyées par une ancienne version de l'iPhone).
    var priority: TaskPriority?
    var category: String?
    var tags: [String]?
    /// Liste d'articles (P9-G2) ; `nil` sans liste (et listes envoyées par une ancienne version de l'iPhone).
    var articles: [WatchArticle]?

    var isUrgent: Bool { priority == .urgent }

    func isLate(at now: Date) -> Bool { due.map { $0 < now } ?? false }
}

/// Article d'une liste, tel que la montre l'affiche et le coche.
nonisolated struct WatchArticle: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var texte: String
    var quantite: String?
    var coche: Bool
}

/// Messages échangés entre l'iPhone et la montre (WatchConnectivity).
nonisolated enum WatchLink {
    static let tasksKey = "tasks"
    static let actionKey = "action"
    static let idKey = "id"
    static let titleKey = "title"
    static let dueKey = "due"
    static let hasTimeKey = "hasTime"
    static let priorityKey = "priority"
    /// Connexion Google transmise à la montre pour qu'elle parle seule à Google (eSIM).
    static let refreshTokenKey = "googleRefreshToken"
    static let clientIDKey = "googleClientID"
    /// Tâches dans HA : URL de Home Assistant et jeton apps-perso, pour que la montre écrive seule le mémo
    /// (Siri lance la montre en arrière-plan, où l'iPhone n'est pas « joignable »). Chaînes vides = à oublier.
    static let haURLKey = "haURL"
    static let haTokenKey = "haToken"
    /// Les tâches sont dans Home Assistant : la montre ne lit et n'écrit plus les tâches chez Google
    /// (elle n'y verrait que la boîte d'entrée des dictées) et passe par l'iPhone ; le mémo reste chez Google.
    static let tasksInHAKey = "tasksInHA"
    /// Lieu de travail (P9-N2) : libellés des jours travaillés des 14 prochains jours, `{"AAAA-MM-JJ": "🏢 Bureau"}`
    /// (JSON, clés triées). Données vides = rien à afficher. La montre montre celui du jour sans rien demander à HA.
    static let lieuTravailKey = "lieuTravail"
    /// Copie locale de la montre (App Group de la montre), lue aussi par la complication (reste de N2, 28/10/2026).
    static let lieuTravailStoreKey = "watchLieuTravail"

    /// Débuts des jours suivants entre `debut` (exclu) et `fin` (inclus) : la complication change de libellé à minuit
    /// sans rien demander (timeline calculée à l'avance, B6).
    static func minuits(apres debut: Date, jusqua fin: Date, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var jour = calendar.startOfDay(for: debut)
        while let suivant = calendar.date(byAdding: .day, value: 1, to: jour), suivant <= fin {
            dates.append(suivant)
            jour = suivant
        }
        return dates
    }

    static func decodeLieux(_ data: Data?) -> [String: String] {
        data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// Le libellé du jour de `date` (« 🏢 Bureau », « 🏠 Télétravail »…), ou `nil` pour un jour non travaillé.
    static func libelleDuJour(_ lieux: [String: String], date: Date, calendar: Calendar = .current) -> String? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return lieux[String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)]
    }

    enum Action: String {
        case complete, snooze, add
        /// Article coché ou décoché (`idKey` = tâche, `articleKey`, `cocheKey`, `dueKey` = instant de la coche).
        case article
        /// Fiche du mémo de tri (tâches dans Home Assistant) : l'iPhone l'enregistre et répond `outcomeKey`.
        case memo
        /// Position marquée sur la montre (30/10) : `latKey`, `lonKey`, `precisionKey`, `dueKey` = instant du point.
        case position
    }
    static let detailsKey = "details"
    static let latKey = "lat"
    static let lonKey = "lon"
    static let precisionKey = "precision"
    static let articleKey = "article"
    static let cocheKey = "coche"
    /// Réponse de l'iPhone à une fiche du mémo : `added`, `completed`, `unchanged` ou `failed`.
    static let outcomeKey = "outcome"

    static func encode(_ tasks: [WatchTask]) -> Data {
        // Clés triées : la même liste donne toujours les mêmes octets (l'iPhone compare l'état avant de l'envoyer).
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = .sortedKeys
        return (try? encodeur.encode(tasks)) ?? Data()
    }

    static func decode(_ data: Data?) -> [WatchTask] {
        data.flatMap { try? JSONDecoder().decode([WatchTask].self, from: $0) } ?? []
    }
}
