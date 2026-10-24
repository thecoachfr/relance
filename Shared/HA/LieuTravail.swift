import Foundation

/// Le lieu de travail des 14 prochains jours (P9-N2, 24/10/2026), tel que publié par l'app AppDaemon
/// `aiguillage_lieu_travail` dans `sensor.aiguillage_lieu_travail` (contrat `homeassistant/LIEU-TRAVAIL.md`).
/// Aiguillage ne recalcule rien : il affiche `phrase` et les libellés tels quels.
///
/// Lu par l'API REST de HA (`GET /api/states/…`) avec le jeton `apps-perso`, comme « Sur la TV » ; pas de sondage :
/// à la synchro (au plus une lecture tous les `intervalle`), et juste après une modification des réglages.
nonisolated struct LieuTravail: Codable, Equatable, Sendable {
    struct Jour: Codable, Equatable, Sendable, Identifiable {
        /// `AAAA-MM-JJ`.
        var date: String
        /// `lundi`… `dimanche`.
        var jour: String
        /// `bureau`, `lab`, `teletravail`, `off` ou `ferie`.
        var lieu: String
        /// `sur`, `probable` ou `constate`.
        var certitude: String
        /// `semaine`, `premier_vendredi`, `exception`, `ferie` ou `position`.
        var source: String
        /// « 🏢 Bureau », « 🏢 Bureau ? », « 🧪 Le Lab », « 🏠 Télétravail », « Pas Barrière », « Férié ».
        var libelle: String
        /// Lieu prévu quand la position l'a contredit.
        var prevu: String?

        var id: String { date }
        /// Jour travaillé chez Barrière (bureau, Lab ou télétravail).
        var estTravaille: Bool { LieuTravail.travailles.contains(lieu) }
    }

    static let entite = "sensor.aiguillage_lieu_travail"
    static let travailles: Set<String> = ["bureau", "lab", "teletravail"]
    /// Au plus une lecture du capteur par quart d'heure (il est recalculé toutes les 15 min côté HA).
    static let intervalle: TimeInterval = 15 * 60

    var etat: String
    var phrase: String
    var jours: [Jour]
    var suggestion: String?
    var maj: String?

    // MARK: - Lecture

    /// Le capteur d'après la réponse de `GET /api/states/<entité>` ; `nil` s'il est indisponible ou illisible.
    init?(etatHA data: Data) {
        guard let racine = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let etat = racine["state"] as? String, !["unavailable", "unknown", ""].contains(etat),
              let attributs = racine["attributes"] as? [String: Any],
              let phrase = attributs["phrase"] as? String, !phrase.isEmpty else { return nil }
        let jours = (attributs["jours"] as? [Any] ?? []).compactMap { brut -> Jour? in
            guard let objet = brut as? [String: Any],
                  let donnees = try? JSONSerialization.data(withJSONObject: objet) else { return nil }
            return try? JSONDecoder().decode(Jour.self, from: donnees)
        }
        (self.etat, self.phrase, self.jours) = (etat, phrase, jours)
        suggestion = attributs["suggestion"] as? String
        maj = attributs["maj"] as? String
    }

    init(etat: String, phrase: String, jours: [Jour], suggestion: String? = nil, maj: String? = nil) {
        (self.etat, self.phrase, self.jours, self.suggestion, self.maj) = (etat, phrase, jours, suggestion, maj)
    }

    enum Lecture: Equatable, Sendable {
        case lu(LieuTravail)
        /// Capteur absent (404) ou indisponible : le bandeau se cache.
        case absent
    }

    struct Erreur: LocalizedError {
        var statut: Int
        var errorDescription: String? { "Home Assistant a répondu \(statut) pour le lieu de travail." }
    }

    /// Lit le capteur ; lève une erreur seulement si HA ne répond pas ou refuse (le dernier état connu est gardé).
    static func lire(url: URL, jeton: String) async throws -> Lecture {
        var requete = URLRequest(url: url.appending(path: "api/states/\(entite)"), timeoutInterval: 10)
        requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        let (donnees, reponse) = try await Reseau.envoyer(requete, rejouable: true)
        let statut = reponse?.statusCode ?? 0
        if statut == 404 { return .absent }
        guard (200..<300).contains(statut) else { throw Erreur(statut: statut) }
        return LieuTravail(etatHA: donnees).map(Lecture.lu) ?? .absent
    }

    // MARK: - Copie dans l'App Group (affichage immédiat au lancement, montre)

    private static let cacheKey = "lieuTravail"

    static func cached() -> LieuTravail? {
        AppGroup.defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(LieuTravail.self, from: $0) }
    }

    static func cache(_ lieu: LieuTravail?) {
        if let lieu, let donnees = try? JSONEncoder().encode(lieu) {
            AppGroup.defaults.set(donnees, forKey: cacheKey)
        } else {
            AppGroup.defaults.removeObject(forKey: cacheKey)
        }
    }

    // MARK: - Calculs simples sur les jours publiés

    /// Le jour `AAAA-MM-JJ` d'une date (fuseau du calendrier).
    static func cle(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func date(_ cle: String, calendar: Calendar = .current) -> Date? {
        let p = cle.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    func jour(_ date: Date, calendar: Calendar = .current) -> Jour? {
        let cle = Self.cle(date, calendar: calendar)
        return jours.first { $0.date == cle }
    }

    /// Prochain jour (aujourd'hui compris) qui convient au contexte, ou `nil` s'il n'y en a pas dans les 14 jours
    /// publiés : la tâche reste alors sans date. Même règle que `aiguillage_tri.jour_pour_contexte`.
    func prochainJour(pour contexte: ContexteTache, aPartirDe aujourdhui: Date = .now,
                      calendar: Calendar = .current) -> Date? {
        let debut = Self.cle(aujourdhui, calendar: calendar)
        return jours.first { $0.date >= debut && contexte.lieuxDuJour.contains($0.lieu) }
            .flatMap { Self.date($0.date, calendar: calendar) }
    }

    /// Libellés des jours travaillés, par date, pour la montre (`WatchLink.lieuTravailKey`) : elle affiche celui du
    /// jour sans rien demander à HA. Octets stables (clés triées) : l'iPhone compare avant d'envoyer.
    var pourLaMontre: Data {
        let libelles = Dictionary(jours.filter(\.estTravaille).map { ($0.date, $0.libelle) }, uniquingKeysWith: { a, _ in a })
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = .sortedKeys
        return (try? encodeur.encode(libelles)) ?? Data()
    }
}
