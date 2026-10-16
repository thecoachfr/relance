import DonneesHA
import Foundation

/// Recette partagée (P9-G3) : lue dans les données structurées schema.org `Recipe` de la page (JSON-LD), sans IA.
/// Les ingrédients restent bruts (« 2 steaks d'échine de porc », « 400 g Spaghetti ») : la routine de tri en fait
/// des articles (texte court en français, quantité indicative pour le nombre de parts, rayon).
nonisolated struct SharedRecipe: Equatable, Sendable {
    var titre: String
    var ingredients: [String]
    /// Nombre de parts annoncé par la recette (`recipeYield`), si lisible.
    var parts: Int?

    /// La recette de la page, `nil` sans données `Recipe` ou sans ingrédient. Lecture limitée à 4 s.
    static func fetch(_ url: URL) async -> SharedRecipe? {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data.prefix(1_500_000), encoding: .utf8)
                ?? String(data: data.prefix(1_500_000), encoding: .isoLatin1) else { return nil }
        return recipe(inHTML: html)
    }

    static func recipe(inHTML html: String) -> SharedRecipe? {
        let pattern = #"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return nil }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let json = try? JSONSerialization.jsonObject(with: Data(html[range].utf8)) else { continue }
            if let recipe = find(in: json) { return recipe }
        }
        return nil
    }

    /// Cherche un objet `Recipe` dans le JSON-LD (à la racine, dans une liste, dans `@graph` ou `mainEntity`).
    private static func find(in json: Any) -> SharedRecipe? {
        if let list = json as? [Any] { return list.lazy.compactMap(find).first }
        guard let object = json as? [String: Any] else { return nil }
        let types = (object["@type"] as? [String]) ?? [(object["@type"] as? String) ?? ""]
        if types.contains("Recipe") {
            let ingredients = ((object["recipeIngredient"] as? [Any]) ?? (object["ingredients"] as? [Any]) ?? [])
                .compactMap { $0 as? String }.map(cleaned).filter { !$0.isEmpty }
            guard !ingredients.isEmpty else { return nil }
            return SharedRecipe(titre: cleaned(object["name"] as? String ?? "Recette"), ingredients: ingredients,
                                parts: parts(object["recipeYield"]))
        }
        for key in ["@graph", "mainEntity"] {
            if let found = object[key].flatMap(find) { return found }
        }
        return nil
    }

    /// « 4 », 4, ["4", "4 personnes"], « 2 parts » → le premier nombre.
    static func parts(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let list = value as? [Any] { return list.lazy.compactMap(parts).first }
        guard let text = value as? String, let m = text.firstMatch(of: /\d+/) else { return nil }
        return Int(m.0)
    }

    /// Entités HTML décodées, espaces resserrés.
    static func cleaned(_ text: String) -> String {
        var t = text
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#039;", "'"), ("&#39;", "'"), ("&#x27;", "'"),
                               ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&rsquo;", "’"),
                               ("&eacute;", "é"), ("&egrave;", "è"), ("&agrave;", "à"), ("&ccedil;", "ç"), ("&oelig;", "œ")] {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Texte partagé qui ressemble à une recette (mot « ingrédients » en français, italien ou anglais).
    static func looksLikeRecipe(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["ingrédient", "ingredient", "ingredienti"].contains { t.contains($0) }
    }

    /// Ce qui part dans `liste.recettes` : la routine de tri en tire les articles (`a_preparer`), puis le passe à
    /// `false`. Pour une recette collée en texte libre, `texte` remplace `ingredients`.
    func entree(lien: URL?) -> JSONValeur {
        var entree: [String: JSONValeur] = ["titre": .texte(titre), "a_preparer": .booleen(true),
                                            "ingredients": .liste(ingredients.map { .texte($0) })]
        if let lien { entree["lien"] = .texte(lien.absoluteString) }
        if let parts { entree["parts"] = .entier(parts) }
        return .objet(entree)
    }

    /// Recette collée en texte : tout le texte part à la routine, qui y trouve les ingrédients.
    static func entree(texte: String, titre: String) -> JSONValeur {
        .objet(["titre": .texte(titre), "a_preparer": .booleen(true), "texte": .texte(String(texte.prefix(8000)))])
    }
}
