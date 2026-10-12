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

    var isUrgent: Bool { priority == .urgent }

    func isLate(at now: Date) -> Bool { due.map { $0 < now } ?? false }
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

    enum Action: String {
        case complete, snooze, add
    }

    static func encode(_ tasks: [WatchTask]) -> Data {
        (try? JSONEncoder().encode(tasks)) ?? Data()
    }

    static func decode(_ data: Data?) -> [WatchTask] {
        data.flatMap { try? JSONDecoder().decode([WatchTask].self, from: $0) } ?? []
    }
}
