import DonneesHA
import Foundation

/// Recette d'action (P9-D2) : « si la tâche remplit ces conditions, lui ajouter cette action ». Rangées dans
/// Home Assistant sous `config:recettes` (`{"recettes": [...]}`), appliquées par la vigie ; l'app les montre et
/// les active ou les coupe. Le JSON est gardé entier : seul `active` est modifié par l'app.
nonisolated struct Recette: Identifiable, Equatable, Sendable {
    static let haKey = "config:recettes"

    var valeur: [String: JSONValeur]

    var id: String { texte("id") ?? "" }
    var nom: String { texte("nom") ?? id }
    var active: Bool {
        get { if case .booleen(let b)? = valeur["active"] { b } else { false } }
        set { valeur["active"] = .booleen(newValue) }
    }

    /// « Envie À écouter · lien spotify.com » : les conditions, lisibles.
    var conditions: String {
        guard case .objet(let si)? = valeur["si"] else { return "" }
        var parts: [String] = []
        if case .texte(let t)? = si["envie_type"] {
            parts.append(ToSee.Kind(haType: t).map { "Envie \($0.title)" } ?? "Envie \(t)")
        }
        if case .texte(let h)? = si["hote"] { parts.append("lien \(h)") }
        if case .texte(let c)? = si["categorie"] { parts.append("catégorie \(c)") }
        if case .texte(let t)? = si["tag"] { parts.append("tag \(t)") }
        if case .texte(let m)? = si["mot"] { parts.append("« \(m) » dans le titre") }
        return parts.joined(separator: " · ")
    }

    /// Qui l'exécute : « par Home Assistant », « par une routine Claude ».
    var executant: String {
        guard case .objet(let alors)? = valeur["alors"], case .texte(let e)? = alors["executant"] else { return "" }
        return switch e {
        case "ha": "par Home Assistant"
        case "routine": "par une routine Claude"
        default: "sur l'appareil"
        }
    }

    private func texte(_ cle: String) -> String? { if case .texte(let s)? = valeur[cle] { s } else { nil } }

    /// Recettes de la valeur de `config:recettes`.
    static func liste(_ config: JSONValeur) -> [Recette] {
        guard case .objet(let o) = config, case .liste(let l)? = o["recettes"] else { return [] }
        return l.compactMap { if case .objet(let r) = $0 { Recette(valeur: r) } else { nil } }
    }

    static func config(_ recettes: [Recette]) -> JSONValeur {
        .objet(["recettes": .liste(recettes.map { .objet($0.valeur) })])
    }
}
