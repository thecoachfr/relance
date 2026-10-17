import DonneesHA
import Foundation

/// Mes lieux habituels, rangés en groupes (« Supermarchés », « Pharmacies »…), P9-H2 : une tâche rattachée à un
/// groupe me prévient en passant près de N'IMPORTE LEQUEL de ses lieux. Rangés dans Home Assistant sous la clé
/// `config:lieux` (ignorée par la routine de tri, la vigie et le Nest Hub, comme `config:abonnements`), et dans
/// l'App Group pour la surveillance des zones hors ligne.
nonisolated struct MesLieux: Codable, Equatable, Sendable {
    struct Lieu: Codable, Equatable, Sendable, Identifiable, Hashable {
        var id: String = UUID().uuidString.lowercased()
        var nom: String
        var adresse: String?
        var lat: Double
        var lon: Double
    }

    struct Groupe: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var nom: String
        var lieux: [Lieu] = []
    }

    var groupes: [Groupe] = []
    /// Mon domicile : proposé en tête de la recherche de lieu (« Maison »), pour les tâches de la maison.
    var domicile: Lieu?

    static let haKey = "config:lieux"
    private static let cacheKey = "mesLieux"
    /// Groupe des listes d'achats, rattaché automatiquement (créé vide s'il n'existe pas).
    static let supermarches = "supermarches"
    static let parDefaut = MesLieux(groupes: [Groupe(id: supermarches, nom: "Supermarchés")])

    func groupe(_ id: String) -> Groupe? { groupes.first { $0.id == id } }

    /// Le lieu et son groupe, d'après l'identifiant du lieu.
    func lieu(_ id: String) -> (lieu: Lieu, groupe: Groupe)? {
        for g in groupes { if let l = g.lieux.first(where: { $0.id == id }) { return (l, g) } }
        return nil
    }

    /// La ligne 📍 d'un de mes lieux : nom, adresse, et lien Plans du point (coordonnées gardées).
    static func contact(_ lieu: Lieu) -> TaskContact {
        TaskContact(name: lieu.nom, address: lieu.adresse,
                    link: TaskContact.mapsLink(name: lieu.nom, latitude: lieu.lat, longitude: lieu.lon))
    }

    // MARK: - Home Assistant et cache

    var valeur: JSONValeur { (try? JSONValeur(self)) ?? .objet([:]) }

    init(groupes: [Groupe] = [], domicile: Lieu? = nil) { (self.groupes, self.domicile) = (groupes, domicile) }

    init?(valeur: JSONValeur) {
        guard let lu = try? valeur.decoder(MesLieux.self) else { return nil }
        self = lu
    }

    static func cached() -> MesLieux {
        AppGroup.defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(MesLieux.self, from: $0) } ?? parDefaut
    }

    static func cache(_ lieux: MesLieux) {
        AppGroup.defaults.set(try? JSONEncoder().encode(lieux), forKey: cacheKey)
    }
}

/// Rattachement d'une tâche à des groupes de lieux (P9-H2).
extension TaskItem {
    /// Groupes dont un lieu proche doit rappeler cette tâche : ceux de ses actions « Me le rappeler près de… »,
    /// plus « Supermarchés » pour une liste d'achats pas finie.
    var groupesDeLieux: [String] {
        guard !isCompleted, !isTrashed else { return [] }
        var groupes = actions.filter { $0.type == TacheHA.Action.rappelGroupe && $0.etat == "a_faire" }.compactMap(\.groupe)
        if category == "Achats", let liste, !liste.articles.isEmpty, !liste.toutCoché {
            groupes.append(MesLieux.supermarches)
        }
        return Array(Set(groupes)).sorted()
    }
}
