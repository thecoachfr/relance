import Foundation

/// Liens profonds `relance://` (28/10/2026), pour que d'autres apps (Courrier) ouvrent Aiguillage au bon endroit :
/// - `relance://tache/<clé>` : la fiche d'une tâche. Clé = celle de la tâche dans Home Assistant (UUID en minuscules,
///   espace `aiguillage` de `donnees_apps`), ou son identifiant Google Tasks en mode Google ;
/// - `relance://memo/<id>` : une fiche du mémo pour le tri (identifiant de l'élément de la liste) ;
/// - `relance://nouvelle` : la saisie rapide (déjà utilisé par la commande du Centre de contrôle).
/// Documenté dans le README (section « Liens »). Code pur, testé (`LienAiguillageTests`).
nonisolated enum LienAiguillage: Equatable, Sendable {
    case nouvelle
    case tache(String)
    case memo(String)

    static let schema = "relance"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.schema, let hote = url.host()?.lowercased() else { return nil }
        // Identifiant : premier morceau du chemin, décodé (`%20`…) et sans espaces autour.
        let morceau = url.pathComponents.first { $0 != "/" }?
            .removingPercentEncoding?.trimmingCharacters(in: .whitespaces) ?? ""
        switch hote {
        case "nouvelle": self = .nouvelle
        case "tache" where !morceau.isEmpty: self = .tache(morceau)
        case "memo" where !morceau.isEmpty: self = .memo(morceau)
        default: return nil
        }
    }

    /// Le lien d'une tâche ou d'une fiche (pour le copier ou le donner à une autre app).
    var url: URL {
        func encode(_ id: String) -> String {
            id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
        }
        switch self {
        case .nouvelle: return URL(string: "\(Self.schema)://nouvelle")!
        case .tache(let cle): return URL(string: "\(Self.schema)://tache/\(encode(cle))")!
        case .memo(let id): return URL(string: "\(Self.schema)://memo/\(encode(id))")!
        }
    }

    /// La tâche désignée par une clé : UUID local (clé HA), sinon identifiant Google.
    static func tache(_ cle: String, local: (UUID) -> TaskItem?, google: (String) -> TaskItem?) -> TaskItem? {
        if let id = UUID(uuidString: cle), let item = local(id) { return item }
        return google(cle)
    }

    /// La fiche du mémo désignée par un identifiant ; à défaut, par son sujet (sans tenir compte des majuscules et des
    /// accents), pour un lien écrit à la main (« relance://memo/Dentiste »).
    static func fiche(_ id: String, dans fiches: [MemoEntry]) -> MemoEntry? {
        if let fiche = fiches.first(where: { $0.id == id }) { return fiche }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return fiches.first { $0.title.trimmingCharacters(in: .whitespaces).compare(id, options: options) == .orderedSame }
    }
}
