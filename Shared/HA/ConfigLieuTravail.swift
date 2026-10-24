import DonneesHA
import Foundation

/// Réglages du lieu de travail (P9-N2, 24/10/2026) : enregistrement `config:lieu_travail` de l'espace `aiguillage`
/// (format dans `homeassistant/LIEU-TRAVAIL.md`, validé côté HA par `aiguillage_lieu_travail.config_valide`).
///
/// L'app ne réécrit jamais l'objet entier à partir de ce qu'elle comprend : chaque changement est une
/// `Modification` appliquée sur la valeur lue (`appliquer`), pour garder intacts les champs qu'elle ne connaît pas.
/// En cas de conflit de version (consigne Signal écrite en même temps), la synchro relit la valeur de HA et y
/// réapplique les modifications en attente (`TaskStore.fusionner`).
nonisolated struct ConfigLieuTravail: Equatable, Sendable {
    static let haKey = "config:lieu_travail"
    static let jours = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
    /// Lieux qu'on peut régler (`ferie` vient du calendrier, pas d'un réglage).
    static let lieux = ["bureau", "lab", "teletravail", "off"]
    /// Exceptions gardées 30 jours après leur date, comme côté HA (`GARDE_EXCEPTIONS_JOURS`).
    static let gardeExceptions = 30

    struct Regle: Equatable, Sendable {
        var lieu: String
        var probable: Bool
    }

    /// Semaine type, par nom de jour.
    var semaine: [String: Regle]
    /// Premier vendredi du mois ; `nil` = comme la semaine type.
    var premierVendredi: Regle?
    /// Exceptions `AAAA-MM-JJ` → lieu.
    var exceptions: [String: String]

    /// Valeurs par défaut de HA (`CONFIG_DEFAUT`), pour un enregistrement absent.
    static let parDefaut = ConfigLieuTravail(
        semaine: ["lundi": Regle(lieu: "bureau", probable: false), "mardi": Regle(lieu: "teletravail", probable: false),
                  "mercredi": Regle(lieu: "bureau", probable: true), "jeudi": Regle(lieu: "teletravail", probable: false),
                  "vendredi": Regle(lieu: "off", probable: false), "samedi": Regle(lieu: "off", probable: false),
                  "dimanche": Regle(lieu: "off", probable: false)],
        premierVendredi: Regle(lieu: "bureau", probable: false), exceptions: [:])

    /// Lecture tolérante, complétée par les défauts (comme `config_valide`).
    init(valeur: JSONValeur?) {
        self = Self.parDefaut
        guard case .objet(let o)? = valeur else { return }
        if case .objet(let semaine)? = o["semaine"] {
            for (nom, brut) in semaine where Self.jours.contains(nom) {
                if let regle = Self.regle(brut) { self.semaine[nom] = regle }
            }
        }
        if let pv = o["premier_vendredi"] {
            if case .null = pv { premierVendredi = nil } else if let regle = Self.regle(pv) { premierVendredi = regle }
        }
        if case .objet(let exc)? = o["exceptions"] {
            exceptions = [:]
            for (jour, brut) in exc {
                if case .texte(let lieu) = brut, Self.lieux.contains(lieu), LieuTravail.date(jour) != nil {
                    exceptions[jour] = lieu
                }
            }
        }
    }

    init(semaine: [String: Regle], premierVendredi: Regle?, exceptions: [String: String]) {
        (self.semaine, self.premierVendredi, self.exceptions) = (semaine, premierVendredi, exceptions)
    }

    private static func regle(_ v: JSONValeur) -> Regle? {
        guard case .objet(let r) = v, case .texte(let lieu)? = r["lieu"], lieux.contains(lieu) else { return nil }
        var probable = false
        if case .texte(let c)? = r["certitude"] { probable = c == "probable" }
        return Regle(lieu: lieu, probable: probable)
    }

    // MARK: - Modifications

    enum Modification: Equatable, Sendable {
        /// Jour de la semaine type.
        case semaine(jour: String, Regle)
        /// Premier vendredi du mois ; `nil` = comme la semaine type.
        case premierVendredi(Regle?)
        /// Exception d'un jour `AAAA-MM-JJ` ; `nil` = « Comme prévu » (retire l'exception).
        case exception(date: String, lieu: String?)
    }

    /// La valeur à écrire : `valeur` (lue dans la base locale ou chez HA, `nil` si absente) avec les modifications,
    /// tout le reste gardé tel quel ; les exceptions de plus de 30 jours sont retirées au passage.
    static func appliquer(_ modifications: [Modification], a valeur: JSONValeur?, aujourdhui: Date = .now,
                          calendar: Calendar = .current) -> JSONValeur {
        var o: [String: JSONValeur]
        if case .objet(let lu)? = valeur { o = lu } else { o = Self.defautBrut }
        if o["v"] == nil { o["v"] = .entier(1) }
        for modification in modifications {
            switch modification {
            case .semaine(let jour, let regle):
                guard jours.contains(jour) else { continue }
                var semaine: [String: JSONValeur] = [:]
                if case .objet(let s)? = o["semaine"] { semaine = s }
                semaine[jour] = .objet(brut(regle, garder: semaine[jour]))
                o["semaine"] = .objet(semaine)
            case .premierVendredi(let regle):
                o["premier_vendredi"] = regle.map { .objet(brut($0, garder: o["premier_vendredi"])) } ?? .null
            case .exception(let date, let lieu):
                var exc: [String: JSONValeur] = [:]
                if case .objet(let e)? = o["exceptions"] { exc = e }
                if let lieu, lieux.contains(lieu) { exc[date] = .texte(lieu) } else { exc[date] = nil }
                o["exceptions"] = .objet(exc)
            }
        }
        if case .objet(var exc)? = o["exceptions"],
           let limite = calendar.date(byAdding: .day, value: -gardeExceptions, to: calendar.startOfDay(for: aujourdhui)) {
            let cleLimite = LieuTravail.cle(limite, calendar: calendar)
            for jour in exc.keys where jour < cleLimite { exc[jour] = nil }
            o["exceptions"] = .objet(exc)
        }
        return .objet(o)
    }

    /// Une règle en JSON, en gardant les autres champs de l'ancienne (`garder`).
    private static func brut(_ regle: Regle, garder ancienne: JSONValeur?) -> [String: JSONValeur] {
        var r: [String: JSONValeur] = [:]
        if case .objet(let a)? = ancienne { r = a }
        r["lieu"] = .texte(regle.lieu)
        r["certitude"] = .texte(regle.probable ? "probable" : "sur")
        return r
    }

    private static var defautBrut: [String: JSONValeur] {
        var semaine: [String: JSONValeur] = [:]
        for (nom, regle) in parDefaut.semaine { semaine[nom] = .objet(brut(regle, garder: nil)) }
        return ["v": .entier(1), "semaine": .objet(semaine),
                "premier_vendredi": .objet(brut(parDefaut.premierVendredi!, garder: nil)), "exceptions": .objet([:])]
    }

    // MARK: - Libellés (mêmes mots que le capteur)

    static func libelle(_ lieu: String) -> String {
        switch lieu {
        case "bureau": "🏢 Bureau"
        case "lab": "🧪 Le Lab"
        case "teletravail": "🏠 Télétravail"
        case "ferie": "Férié"
        default: "Pas Barrière"
        }
    }
}
