import DonneesHA
import Foundation

/// Pièces jointes d'une tâche (P9-K) : le fichier est rangé dans Home Assistant (`donnees_apps` 0.3.0, identifiant =
/// SHA-256 du contenu) ; la tâche garde ses métadonnées et le début de son texte, lu sur l'appareil, pour la routine
/// de tri. La ligne `📎 2 pièces jointes` des notes en est la copie pour les lecteurs qui ne connaissent pas le champ.
nonisolated extension TacheHA {
    struct Piece: Codable, Equatable, Sendable, Identifiable, Hashable {
        /// SHA-256 du contenu, identifiant du fichier dans HA.
        var id: String
        var nom: String
        /// Type MIME (`image/jpeg`, `application/pdf`…).
        var type: String
        var taille: Int
        var ajouteLe: String?
        /// `partage`, `photo`, `fichier`, `scan`.
        var source: String?
        /// Début du texte lu sur l'appareil (Vision, PDFKit), 1 500 caractères au plus.
        var texte: String?
        var autres: [String: JSONValeur] = [:]

        init(id: String, nom: String, type: String, taille: Int, ajouteLe: String? = nil, source: String? = nil,
             texte: String? = nil) {
            (self.id, self.nom, self.type, self.taille) = (id, nom, type, taille)
            (self.ajouteLe, self.source, self.texte) = (ajouteLe, source, texte)
        }

        static let longueurTexte = 1500
        static let maxParTache = 5

        var estImage: Bool { type.hasPrefix("image/") }
        var estPDF: Bool { type == "application/pdf" }

        private static let known = ["id", "nom", "type", "taille", "ajoute_le", "source", "texte"]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = try c.decode(String.self, forKey: AnyKey("id"))
            nom = try c.decodeIfPresent(String.self, forKey: AnyKey("nom")) ?? "Pièce jointe"
            type = try c.decodeIfPresent(String.self, forKey: AnyKey("type")) ?? "application/octet-stream"
            taille = try c.decodeIfPresent(Int.self, forKey: AnyKey("taille")) ?? 0
            ajouteLe = try c.decodeIfPresent(String.self, forKey: AnyKey("ajoute_le"))
            source = try c.decodeIfPresent(String.self, forKey: AnyKey("source"))
            texte = try c.decodeIfPresent(String.self, forKey: AnyKey("texte"))
            for key in c.allKeys where !Self.known.contains(key.stringValue) {
                autres[key.stringValue] = try c.decode(JSONValeur.self, forKey: key)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: AnyKey.self)
            try c.encode(id, forKey: AnyKey("id"))
            try c.encode(nom, forKey: AnyKey("nom"))
            try c.encode(type, forKey: AnyKey("type"))
            try c.encode(taille, forKey: AnyKey("taille"))
            try c.encodeIfPresent(ajouteLe, forKey: AnyKey("ajoute_le"))
            try c.encodeIfPresent(source, forKey: AnyKey("source"))
            try c.encodeIfPresent(texte, forKey: AnyKey("texte"))
            for (key, value) in autres where !Self.known.contains(key) { try c.encode(value, forKey: AnyKey(key)) }
        }

        /// Copie lisible dans les notes : `📎 2 pièces jointes`.
        static let marque = "📎"

        static func notes(_ notes: String, setting pieces: [Piece]) -> String {
            var lignes = notes.isEmpty ? [] : notes.components(separatedBy: "\n")
            lignes.removeAll { $0.hasPrefix(marque + " ") && $0.contains("pièce") }
            if !pieces.isEmpty {
                lignes.append(pieces.count == 1 ? "\(marque) 1 pièce jointe" : "\(marque) \(pieces.count) pièces jointes")
            }
            return lignes.joined(separator: "\n")
        }
    }
}
