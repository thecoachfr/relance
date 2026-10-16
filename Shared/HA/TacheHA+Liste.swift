import DonneesHA
import Foundation

/// Liste d'articles cochables d'une tâche (P9-G : courses, valise, matériel…). Le champ `liste` fait foi ; la ligne
/// `🛒 Liste : 3/12 cochés` des notes en est la copie pour les lecteurs qui ne le connaissent pas (Nest Hub, mode
/// Google). Les champs inconnus (de la liste et des articles) sont gardés tels quels.
nonisolated extension TacheHA {
    struct Liste: Codable, Equatable, Sendable {
        struct Article: Codable, Equatable, Sendable, Identifiable {
            var id: String
            var texte: String
            /// Texte libre, toujours indicatif (« 200 g », « 1 bouquet », « 6 »).
            var quantite: String?
            /// `fruits_legumes`, `frais`, `epicerie`, `boissons`, `hygiene`, `maison`, `placard`, `autre`.
            var rayon: String?
            var coche = false
            /// Horodatage ISO 8601 du dernier changement de l'article : arbitre la fusion entre deux appareils.
            var maj: String?
            /// `saisie`, `recette`, `dictee`, `routine`.
            var source: String?
            var autres: [String: JSONValeur] = [:]

            init(id: String = UUID().uuidString.lowercased(), texte: String, quantite: String? = nil,
                 rayon: String? = nil, coche: Bool = false, maj: String? = nil, source: String? = "saisie") {
                (self.id, self.texte, self.quantite, self.rayon) = (id, texte, quantite, rayon)
                (self.coche, self.maj, self.source) = (coche, maj, source)
            }

            private static let known = ["id", "texte", "quantite", "rayon", "coche", "maj", "source"]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                id = try c.decode(String.self, forKey: AnyKey("id"))
                texte = try c.decodeIfPresent(String.self, forKey: AnyKey("texte")) ?? ""
                quantite = try c.decodeIfPresent(String.self, forKey: AnyKey("quantite"))
                rayon = try c.decodeIfPresent(String.self, forKey: AnyKey("rayon"))
                coche = try c.decodeIfPresent(Bool.self, forKey: AnyKey("coche")) ?? false
                maj = try c.decodeIfPresent(String.self, forKey: AnyKey("maj"))
                source = try c.decodeIfPresent(String.self, forKey: AnyKey("source"))
                for key in c.allKeys where !Self.known.contains(key.stringValue) {
                    autres[key.stringValue] = try c.decode(JSONValeur.self, forKey: key)
                }
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: AnyKey.self)
                try c.encode(id, forKey: AnyKey("id"))
                try c.encode(texte, forKey: AnyKey("texte"))
                try c.encodeIfPresent(quantite, forKey: AnyKey("quantite"))
                try c.encodeIfPresent(rayon, forKey: AnyKey("rayon"))
                try c.encode(coche, forKey: AnyKey("coche"))
                try c.encodeIfPresent(maj, forKey: AnyKey("maj"))
                try c.encodeIfPresent(source, forKey: AnyKey("source"))
                for (key, value) in autres where !Self.known.contains(key) { try c.encode(value, forKey: AnyKey(key)) }
            }
        }

        var articles: [Article] = []
        /// Nombre de parts des recettes (quantités prévues pour ce nombre).
        var parts: Int?
        /// `recettes`, et tout champ ajouté par la routine : gardés tels quels.
        var autres: [String: JSONValeur] = [:]

        init(articles: [Article] = [], parts: Int? = nil) {
            (self.articles, self.parts) = (articles, parts)
        }

        private static let known = ["articles", "parts"]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            // Un article mal formé est ignoré sans perdre les autres.
            let bruts = (try? c.decodeIfPresent([JSONValeur].self, forKey: AnyKey("articles"))) ?? []
            articles = bruts.compactMap { valeur in
                (try? JSONEncoder().encode(valeur)).flatMap { try? JSONDecoder().decode(Article.self, from: $0) }
            }
            parts = try? c.decodeIfPresent(Int.self, forKey: AnyKey("parts"))
            for key in c.allKeys where !Self.known.contains(key.stringValue) {
                autres[key.stringValue] = try c.decode(JSONValeur.self, forKey: key)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: AnyKey.self)
            try c.encode(articles, forKey: AnyKey("articles"))
            try c.encodeIfPresent(parts, forKey: AnyKey("parts"))
            for (key, value) in autres where !Self.known.contains(key) { try c.encode(value, forKey: AnyKey(key)) }
        }

        var cochés: Int { articles.filter(\.coche).count }
        /// Au moins un article, tous cochés : la tâche passe en « Fait ».
        var toutCoché: Bool { !articles.isEmpty && articles.allSatisfy(\.coche) }

        /// Copie lisible dans les notes : `🛒 Liste : 3/12 cochés`.
        var ligne: String { "\(Self.marque) \(cochés)/\(articles.count) cochés" }
        static let marque = "🛒 Liste :"

        /// Les notes avec la ligne `🛒` à jour (remplacée, ou ajoutée à la fin), ou retirée sans liste.
        static func notes(_ notes: String, setting liste: Liste?) -> String {
            var lignes = notes.isEmpty ? [] : notes.components(separatedBy: "\n")
            let i = lignes.firstIndex { $0.hasPrefix(marque) }
            switch (i, liste) {
            case let (i?, liste?): lignes[i] = liste.ligne
            case let (i?, nil): lignes.remove(at: i)
            case let (nil, liste?): lignes.append(liste.ligne)
            case (nil, nil): break
            }
            return lignes.joined(separator: "\n")
        }

        // MARK: - Fusion (deux appareils qui cochent en même temps)

        /// Fusion article par article de deux versions d'une même liste, d'après `base` (la dernière reçue de HA par
        /// cet appareil, ancêtre commun) :
        /// - présent des deux côtés : la modification la plus récente (`maj`) gagne ;
        /// - absent d'un côté mais dans `base` : supprimé là, sauf si l'autre côté l'a modifié depuis `base`
        ///   (on ne perd pas un article par erreur) ;
        /// - absent de `base` : ajouté d'un côté, gardé.
        /// L'ordre est celui de `locale`, puis les articles venus seulement de `serveur`, à leur place relative.
        static func fusion(locale: Liste?, serveur: Liste?, base: Liste?) -> Liste? {
            guard let locale else { return serveur }
            guard let serveur else { return locale }
            let avant = Dictionary((base?.articles ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let enFace = Dictionary(serveur.articles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let ici = Dictionary(locale.articles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            func modifié(_ a: Article) -> Bool { avant[a.id] != a }
            func plusRécent(_ a: Article, que b: Article) -> Bool {
                (TacheHA.date(a.maj) ?? .distantPast) >= (TacheHA.date(b.maj) ?? .distantPast)
            }

            var résultat: [Article] = []
            for a in locale.articles {
                if let b = enFace[a.id] {
                    résultat.append(plusRécent(a, que: b) ? a : b)
                } else if avant[a.id] == nil || modifié(a) {
                    résultat.append(a)  // ajouté ici, ou retiré en face mais modifié ici
                }
            }
            // Articles seulement en face : à placer après leur voisin d'avant dans la liste du serveur.
            for (i, b) in serveur.articles.enumerated() where ici[b.id] == nil {
                guard avant[b.id] == nil || modifié(b) else { continue }  // retiré ici, pas modifié en face
                let précédent = serveur.articles[..<i].last { a in résultat.contains { $0.id == a.id } }
                let position = précédent.flatMap { p in résultat.firstIndex { $0.id == p.id } }.map { $0 + 1 } ?? résultat.count
                résultat.insert(b, at: position)
            }
            var liste = locale
            liste.articles = résultat
            if liste.parts == nil { liste.parts = serveur.parts }
            for (key, value) in serveur.autres where liste.autres[key] == nil { liste.autres[key] = value }
            return liste
        }
    }
}
