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

    enum Action: String {
        case complete, snooze, add
        /// Article coché ou décoché (`idKey` = tâche, `articleKey`, `cocheKey`, `dueKey` = instant de la coche).
        case article
        /// Fiche du mémo de tri (tâches dans Home Assistant) : l'iPhone l'enregistre et répond `outcomeKey`.
        case memo
    }
    static let detailsKey = "details"
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
