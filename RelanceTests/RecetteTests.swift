import DonneesHA
import Foundation
import ImageIO
import Testing
import UIKit
@testable import Relance

/// Recettes partagées (P9-G3) : ingrédients lus dans les données schema.org de la page.
struct RecetteTests {
    /// Forme de carredeboeuf.com (16/10) : `@graph`, entités HTML, nombre de parts en texte.
    @Test func graphEtEntites() throws {
        let html = """
        <html><head><script type="application/ld+json">{"@context":"https://schema.org","@graph":[
          {"@type":"WebPage","name":"x"},
          {"@type":["Recipe"],"name":"Recette de Tonkatsu","recipeYield":"2",
           "recipeIngredient":["2 steaks d&#039;échine de porc","  1 jaune d’œuf   battu ","Chapelure panko"]}]}
        </script></head></html>
        """
        let r = try #require(SharedRecipe.recipe(inHTML: html))
        #expect(r.titre == "Recette de Tonkatsu" && r.parts == 2)
        #expect(r.ingredients == ["2 steaks d'échine de porc", "1 jaune d’œuf battu", "Chapelure panko"])
    }

    /// Forme de dissapore.com (16/10) : objet à la racine, plusieurs blocs JSON-LD, parts en nombre.
    @Test func plusieursBlocs() throws {
        let html = """
        <script type="application/ld+json">{"@type":"Organization","name":"Dissapore"}</script>
        <script type='application/ld+json'>{"@type":"Recipe","name":"Spaghetti alla carbonara","recipeYield":["4","4 persone"],
          "recipeIngredient":["400 g Spaghetti"," q.b. Pepe nero"]}</script>
        """
        let r = try #require(SharedRecipe.recipe(inHTML: html))
        #expect(r.parts == 4 && r.ingredients == ["400 g Spaghetti", "q.b. Pepe nero"])
        #expect(SharedRecipe.recipe(inHTML: "<title>Pas une recette</title>") == nil)
    }

    @Test func entreeEtListe() {
        let r = SharedRecipe(titre: "Carbonara", ingredients: ["400 g Spaghetti"], parts: 4)
        var liste = TacheHA.Liste(parts: r.parts)
        liste.autres["recettes"] = .liste([r.entree(lien: URL(string: "https://exemple.fr/r"))])
        #expect(liste.recettesAPreparer == ["Carbonara"])
        #expect(SharedRecipe.looksLikeRecipe("Ingrédients : 2 œufs…") && !SharedRecipe.looksLikeRecipe("Rappelle Paul"))
        let texte = SharedRecipe.entree(texte: "Ingrédients…", titre: "Gâteau")
        guard case .objet(let o) = texte else { Issue.record("objet attendu"); return }
        #expect(o["a_preparer"] == .booleen(true) && o["texte"] != nil)
    }

    /// Photo d'une page de recette : le texte est lu sur l'appareil (Vision).
    @Test func texteDUnePhoto() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 500)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 500))
            ("Risotto aux champignons\nIngrédients\n300 g de riz arborio\n1 oignon" as NSString)
                .draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 44)])
        }
        let data = try #require(image.pngData())
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let texte = try #require(SharedPhoto.text(in: source))
        #expect(SharedRecipe.looksLikeRecipe(texte))
        #expect(texte.contains("arborio"))
    }
}
