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

// MARK: - Magasin d'une liste (P9-Q, 28/10/2026)

nonisolated extension MesLieux {
    /// Enseignes reconnues dans le titre d'une liste (P9-Q) : nommée, elle seule prévient (décision d'Alexandre,
    /// 28/10). Sans groupe de ce nom dans Mes lieux, la fiche propose de le créer.
    static let enseignes = [
        "Leroy Merlin", "Castorama", "Brico Dépôt", "Bricorama", "Mr Bricolage", "Weldom", "Ikea", "Conforama", "But",
        "Maisons du Monde", "Decathlon", "Go Sport", "Intersport", "Boulanger", "Darty", "Fnac", "Cultura",
        "Nature & Découvertes", "Truffaut", "Jardiland", "Botanic", "Gamm Vert", "Action", "Gifi", "La Foir'Fouille",
        "Picard", "Grand Frais", "Biocoop", "Naturalia", "Lidl", "Aldi", "Carrefour", "Leclerc", "Auchan",
        "Intermarché", "Monoprix", "Franprix", "Casino", "Super U", "Sephora", "Nocibé", "Kiabi", "Zara", "Uniqlo",
        "Norauto", "Feu Vert", "Speedy", "Point P", "Cedeo", "Lapeyre", "Bricomarché", "Apple Store",
    ]

    /// Minuscules, sans accents ni ponctuation, mots séparés par une espace.
    static func normaliser(_ texte: String) -> String {
        let plie = texte.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        let mots = plie.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return mots.joined(separator: " ")
    }

    /// `nom` est dans `titre`, en mots entiers (« leroy merlin » dans « courses a leroy merlin »).
    static func nomme(_ nom: String, dans titre: String) -> Bool {
        let n = normaliser(nom)
        return n.count >= 2 && (" " + normaliser(titre) + " ").contains(" " + n + " ")
    }

    /// Le groupe dont le nom est dans le titre (le plus long d'abord : « Leroy Merlin Ivry » avant « Leroy Merlin »).
    func groupeNomme(dans titre: String) -> Groupe? {
        groupes.filter { Self.nomme($0.nom, dans: titre) }.max { Self.normaliser($0.nom).count < Self.normaliser($1.nom).count }
    }

    /// L'enseigne connue nommée dans le titre, ou `nil`.
    static func enseigne(dans titre: String) -> String? {
        enseignes.filter { nomme($0, dans: titre) }.max { normaliser($0).count < normaliser($1).count }
    }

    /// D'où vient le magasin d'une liste d'achats (règles de P9-Q, dans l'ordre).
    enum Magasin: Equatable {
        /// Action « Me le rappeler près de… » : elle seule.
        case choisi([String])
        /// Groupe nommé dans le titre.
        case nomme(String)
        /// Enseigne connue sans groupe : aucun rappel, la fiche propose de créer le groupe.
        case enseigneSansGroupe(String)
        /// Le défaut, Supermarchés.
        case supermarches
    }

    func magasin(titre: String, actions: [TacheHA.Action]) -> Magasin {
        let choisis = actions.filter { $0.type == TacheHA.Action.rappelGroupe && $0.etat == "a_faire" }.compactMap(\.groupe)
        if !choisis.isEmpty { return .choisi(Array(Set(choisis)).sorted()) }
        if let g = groupeNomme(dans: titre) { return .nomme(g.id) }
        if let e = Self.enseigne(dans: titre) { return .enseigneSansGroupe(e) }
        return .supermarches
    }
}

/// Rattachement d'une tâche à des groupes de lieux (P9-H2, P9-Q).
extension TaskItem {
    var groupesDeLieux: [String] { groupesDeLieux(MesLieux.cached()) }

    /// Groupes dont un lieu proche doit rappeler cette tâche : ceux de ses actions « Me le rappeler près de… » ; pour
    /// une liste d'achats pas finie sans action, le magasin nommé dans le titre, sinon Supermarchés (P9-Q).
    func groupesDeLieux(_ lieux: MesLieux) -> [String] {
        guard !isCompleted, !isTrashed else { return [] }
        let explicites = actions.filter { $0.type == TacheHA.Action.rappelGroupe && $0.etat == "a_faire" }.compactMap(\.groupe)
        guard category == "Achats", let liste, !liste.articles.isEmpty, !liste.toutCoché else {
            return Array(Set(explicites)).sorted()
        }
        return switch lieux.magasin(titre: title, actions: actions) {
        case .choisi(let ids): ids
        case .nomme(let id): [id]
        case .enseigneSansGroupe: []
        case .supermarches: [MesLieux.supermarches]
        }
    }
}
