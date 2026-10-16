import Foundation

/// Plateformes auxquelles Alexandre est abonné (P9-B3) : rangées dans Home Assistant, espace `aiguillage`, sous la
/// clé `config:abonnements` (`{"plateformes": ["netflix", …]}`), que la routine de tri, la vigie et l'écran du
/// Nest Hub ne prennent pas pour une tâche ; gardées aussi dans l'App Group (affichage hors ligne).
nonisolated enum Subscriptions {
    static let haKey = "config:abonnements"
    private static let cacheKey = "subscriptions"

    /// Plateformes proposées dans les réglages (codes de `envie.plateforme`).
    static let choices = ["netflix", "disney", "canal", "prime", "apple_tv", "max", "spotify", "deezer", "apple_music"]

    static func cached() -> [String] {
        AppGroup.defaults.stringArray(forKey: cacheKey) ?? []
    }

    static func cache(_ codes: [String]) {
        AppGroup.defaults.set(codes, forKey: cacheKey)
    }

    /// Les plateformes d'abonnement d'une œuvre qui sont dans mes abonnements (« Netflix »).
    static func included(in availability: Availability, mine: [String] = cached()) -> [Availability.Provider] {
        (availability.subscription + availability.free).filter { $0.code.map(mine.contains) ?? false }
    }
}
