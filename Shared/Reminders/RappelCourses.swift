import Foundation

/// Rappels de passage de la liste de courses unique (P9-U) : elle a presque toujours quelque chose à prendre, et sans
/// frein chaque magasin proche du domicile sonnerait à chaque passage. Décision d'Alexandre (04/11) : un lieu prévient
/// au plus une fois par jour, plus tôt seulement si un article à y prendre est apparu depuis. « Pas aujourd'hui » coupe
/// tous les magasins jusqu'à demain, nouveaux articles compris.
nonisolated struct RappelCourses: Codable, Equatable {
    struct Passage: Codable, Equatable {
        var jour: Date
        var articles: [String]
    }

    /// Dernier rappel par lieu.
    var passages: [String: Passage] = [:]
    var silenceLe: Date?

    private static let cle = "rappelCourses"

    static func charge() -> RappelCourses {
        AppGroup.defaults.data(forKey: cle).flatMap { try? JSONDecoder().decode(RappelCourses.self, from: $0) } ?? RappelCourses()
    }

    func enregistre() {
        AppGroup.defaults.set(try? JSONEncoder().encode(self), forKey: Self.cle)
    }

    /// Faut-il prévenir à ce lieu pour ces articles (identifiants) ?
    func doitPrevenir(lieu: String, articles: [String], now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !articles.isEmpty else { return false }
        if let silenceLe, calendar.isDate(silenceLe, inSameDayAs: now) { return false }
        guard let passage = passages[lieu], calendar.isDate(passage.jour, inSameDayAs: now) else { return true }
        return !Set(articles).isSubset(of: passage.articles)
    }

    /// Note le rappel ; les articles du jour restent connus même s'ils ne sont plus à prendre. Les jours passés sont oubliés.
    mutating func noter(lieu: String, articles: [String], now: Date = .now, calendar: Calendar = .current) {
        passages = passages.filter { calendar.isDate($0.value.jour, inSameDayAs: now) }
        passages[lieu] = Passage(jour: now, articles: Array(Set(articles).union(passages[lieu]?.articles ?? [])).sorted())
    }

    mutating func silence(now: Date = .now) { silenceLe = now }

    /// « Adoucissant, lessive, vinaigre et 2 autres » : assez pour savoir quoi prendre sans ouvrir l'app.
    static func texte(_ noms: [String], maximum: Int = 4) -> String {
        guard noms.count > maximum else { return noms.joined(separator: ", ") }
        let reste = noms.count - maximum
        return noms.prefix(maximum).joined(separator: ", ") + " et \(reste) autre\(reste > 1 ? "s" : "")"
    }
}
