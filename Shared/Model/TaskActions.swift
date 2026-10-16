import DonneesHA
import Foundation

/// Présentation des actions d'une tâche (P9-D1) : libellés, symboles, paramètres, et ce que la vigie a déjà fait
/// sans action explicite (playlist Spotify de D4, notée dans `envie.playlist`).
nonisolated extension TacheHA.Action {
    static let ouvrirLien = "ouvrir_lien"
    static let surTV = "sur_tv"
    static let rappelMaison = "rappel_maison"
    static let rappelPiece = "rappel_piece"
    /// Pièces de la maison (zones de HA), publiées par la vigie sous cette clé : `{"pieces": ["Salon", …]}`.
    static let piecesKey = "config:pieces"

    /// « Me le rappeler dans <pièce> » (P9-F4, Bermuda) : la vigie prévient quand Alexandre y entre, une fois par jour.
    static func dans(_ piece: String) -> Self {
        Self(type: rappelPiece, executant: "ha", declencheur: .objet(["quand": .texte("piece")]),
             params: .objet(["piece": .texte(piece)]))
    }

    var piece: String? {
        guard case .objet(let p)? = params, case .texte(let s)? = p["piece"] else { return nil }
        return s
    }

    /// « Me le rappeler à la maison » (P9-F2) : la vigie prévient quand quelqu'un arrive au salon, une fois par jour.
    static func aLaMaison() -> Self {
        Self(type: rappelMaison, executant: "ha", declencheur: .objet(["quand": .texte("presence")]))
    }

    /// Nouvelle action sur l'appareil, au toucher, avec le lien en paramètre.
    static func surAppareil(_ type: String, lien: URL) -> Self {
        Self(type: type, params: .objet(["lien": .texte(lien.absoluteString)]))
    }

    var titre: String {
        switch type {
        case Self.ouvrirLien: "Ouvrir le lien"
        case Self.surTV: "Sur la TV"
        case Self.rappelMaison: "Me le rappeler à la maison"
        case Self.rappelPiece: "Me le rappeler dans : \(piece ?? "?")"
        case "playlist_spotify": "Ajouter à la playlist « À écouter »"
        case "preparer": "Préparer"
        default: type
        }
    }

    var symbole: String {
        switch type {
        case Self.ouvrirLien: "link"
        case Self.surTV: "tv"
        case Self.rappelMaison: "house"
        case Self.rappelPiece: "figure.walk.arrival"
        case "playlist_spotify": "music.note.list"
        case "preparer": "doc.text.magnifyingglass"
        default: "bolt"
        }
    }

    /// Exécutée par l'appareil quand on la touche (les autres le sont par la vigie ou une routine).
    var auToucher: Bool { executant == "appareil" }

    var lien: URL? {
        guard case .objet(let p)? = params, case .texte(let s)? = p["lien"] else { return nil }
        return URL(string: s)
    }

    /// « Faite le 16/10 à 19:33 · Envoyé à la TV », « Échec · TV injoignable », « À faire ».
    var etatTexte: String {
        let quand = maj.flatMap { TacheHA.date($0) }.map { " le " + $0.formatted(.dateTime.day().month(.twoDigits).hour().minute()) } ?? ""
        if type == Self.rappelMaison || type == Self.rappelPiece, etat == "a_faire" {
            // Reste « à faire » : elle rappelle à chaque passage, une fois par jour, jusqu'à ce que la tâche soit faite.
            let quand = type == Self.rappelMaison ? "En rentrant à la maison" : "En entrant dans : \(piece ?? "?")"
            return [quand, resultat].compactMap { $0 }.joined(separator: " · ")
        }
        let base = switch etat {
        case "faite": "Faite" + quand
        case "echec": "Échec" + quand
        case "en_cours": "En cours"
        default: "À faire"
        }
        return [base, resultat].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Ajout à la playlist Spotify fait par la vigie (D4), lu dans `envie.playlist`.
nonisolated struct PlaylistNote: Equatable, Sendable {
    var ok: Bool
    var jour: String?
    var ajoutes: Int?
    var erreur: String?

    init?(_ envie: TacheHA.Envie?) {
        guard case .objet(let o)? = envie?.autres["playlist"] else { return nil }
        if case .texte(let statut)? = o["statut"] { ok = statut == "ok" } else { return nil }
        if case .texte(let j)? = o["ajoute_le"] ?? o["maj"] { jour = j }
        if case .entier(let n)? = o["ajoutes"] { ajoutes = n }
        if case .texte(let e)? = o["erreur"] { erreur = e }
    }

    /// « Ajoutée le 16/10 (1 titre) » ou « Échec, nouvel essai demain ».
    var texte: String {
        guard ok else { return "Échec, nouvel essai demain" }
        let date = jour.flatMap { j -> String? in
            let p = j.split(separator: "-")
            return p.count == 3 ? "\(p[2])/\(p[1])" : nil
        }
        let titres = ajoutes.map { $0 == 0 ? "déjà dedans" : "\($0) titre\($0 > 1 ? "s" : "")" }
        return ["Ajoutée", date.map { "le \($0)" }, titres.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }
}
