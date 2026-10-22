import CoreLocation
import DonneesHA
import Foundation

/// Un arrêt tel que renvoyé par Home Assistant (heures en secondes Unix).
nonisolated struct ArretTrajet: Decodable, Hashable, Sendable {
    var arrivee: Int
    var depart: Int?
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var debut: Date { Date(timeIntervalSince1970: TimeInterval(arrivee)) }
    var fin: Date? { depart.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

/// Une journée de l'historique (P9-M3) : points `[t, lat, lon]` triés par heure, arrêts, jours voisins.
nonisolated struct JourTrajets: Decodable, Sendable {
    var id: String?
    var jour: String
    var km: Double
    var points: [[Double]]
    var visites: [ArretTrajet]
    var precedent: String?
    var suivant: String?

    /// Morceaux de tracé : un trou de plus de 10 min (ou un saut de plus de 2 km) coupe la ligne.
    static func segments(_ points: [[Double]], trou: TimeInterval = 600, saut: CLLocationDistance = 2000)
        -> [[CLLocationCoordinate2D]] {
        var out: [[CLLocationCoordinate2D]] = []
        var courant: [CLLocationCoordinate2D] = []
        var avant: [Double]?
        for p in points where p.count >= 3 {
            if let a = avant {
                let distance = CLLocation(latitude: a[1], longitude: a[2])
                    .distance(from: CLLocation(latitude: p[1], longitude: p[2]))
                if p[0] - a[0] > trou || distance > saut {
                    if courant.count > 1 { out.append(courant) }
                    courant = []
                }
            }
            courant.append(.init(latitude: p[1], longitude: p[2]))
            avant = p
        }
        if courant.count > 1 { out.append(courant) }
        return out
    }
}

/// « Déjà venu ici ? » : arrêts dans le rayon, et jours où un point est passé tout près.
nonisolated struct DejaVenu: Decodable, Sendable {
    var id: String?
    var visites: [ArretTrajet]
    var jours: [String]
}

/// Questions posées à Home Assistant, qui garde l'historique (app AppDaemon `aiguillage_trajets`) : l'app écrit
/// `demande` dans l'espace `trajets` de `donnees_apps`, Home Assistant répond dans `reponse` avec le même id.
enum TrajetsService {
    static let espace = "trajets"

    enum Erreur: LocalizedError {
        case nonConfigure, sansReponse, refus(String)
        var errorDescription: String? {
            switch self {
            case .nonConfigure: "Home Assistant n'est pas réglé sur cet appareil (Réglages › Home Assistant)."
            case .sansReponse: "Home Assistant n'a pas répondu."
            case .refus(let message): message
            }
        }
    }

    /// Les jours sont ceux de Paris, comme dans Home Assistant.
    static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    /// « 2026-10-22 » → midi ce jour-là.
    static func date(jour: String) -> Date? {
        let parts = jour.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendrier.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func jour(_ date: Date) async throws -> JourTrajets {
        let c = calendrier.dateComponents([.year, .month, .day], from: date)
        let texte = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return try await demander(["type": "jour", "jour": .texte(texte)])
    }

    static func dejaVenu(_ coordinate: CLLocationCoordinate2D, rayon: Double = 150) async throws -> DejaVenu {
        try await demander(["type": "venu", "lat": .nombre(coordinate.latitude), "lon": .nombre(coordinate.longitude),
                            "rayon": .nombre(rayon)])
    }

    private static func demander<R: Decodable>(_ champs: [String: JSONValeur]) async throws -> R {
        guard let url = HAConfig.url, let jeton = HAConfig.token, !jeton.isEmpty else { throw Erreur.nonConfigure }
        let client = HAClient(url: url, jeton: jeton, delai: 15)
        let id = UUID().uuidString.lowercased()
        var valeur = champs
        valeur["id"] = .texte(id)
        _ = try await client.lot(espace: espace, operations: [
            OperationDonnees(type: .ecrire, cle: "demande", valeur: .objet(valeur), versionAttendue: nil,
                             modifieLe: Horodatage.texte(.now), modifiePar: HAConfig.device),
        ])
        // La réponse arrive en moins d'une seconde d'habitude ; au plus 15 s.
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(500))
            guard let reponse = try await client.lire(espace: espace, cle: "reponse"),
                  case .objet(let objet) = reponse.valeur, objet["id"] == .texte(id) else { continue }
            if case .texte(let erreur)? = objet["erreur"] { throw Erreur.refus(erreur) }
            return try reponse.valeur.decoder(R.self)
        }
        throw Erreur.sansReponse
    }
}
