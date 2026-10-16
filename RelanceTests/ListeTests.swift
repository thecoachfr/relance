import DonneesHA
import Foundation
import Testing
@testable import Relance

/// Listes d'articles cochables (P9-G) : format dans HA, ligne des notes, fusion entre deux appareils.
struct ListeTests {
    typealias Liste = TacheHA.Liste
    typealias Article = TacheHA.Liste.Article

    static func article(_ id: String, _ texte: String, coche: Bool = false, maj: String = "2026-10-16T20:00:00Z") -> Article {
        Article(id: id, texte: texte, coche: coche, maj: maj)
    }

    @Test func formatEtChampsInconnus() throws {
        let json = """
        {"titre": "Courses", "fait": false, "v": 2,
         "liste": {"articles": [{"id": "a", "texte": "Œufs", "quantite": "6", "rayon": "frais", "coche": false,
                                 "maj": "2026-10-16T12:00:00Z", "source": "recette", "marque": "bio"},
                                {"pas_d_id": true}],
                   "parts": 4, "recettes": [{"titre": "Risotto"}]}}
        """
        let tache = try JSONDecoder().decode(TacheHA.self, from: Data(json.utf8))
        let liste = try #require(tache.liste)
        #expect(liste.articles.count == 1)  // l'article sans id est ignoré, pas toute la liste
        #expect(liste.articles[0].quantite == "6" && liste.articles[0].autres["marque"] == .texte("bio"))
        #expect(liste.parts == 4 && liste.autres["recettes"] != nil)
        let relu = try JSONDecoder().decode(TacheHA.self, from: JSONEncoder().encode(tache))
        #expect(relu.liste == liste)
        #expect(relu.autres["liste"] == nil)
    }

    @Test func ligneDesNotes() {
        var liste = Liste(articles: [Self.article("a", "Lait", coche: true), Self.article("b", "Pain")])
        #expect(liste.ligne == "🛒 Liste : 1/2 cochés")
        let notes = Liste.notes("Pour samedi", setting: liste)
        #expect(notes == "Pour samedi\n🛒 Liste : 1/2 cochés")
        liste.articles[1].coche = true
        #expect(Liste.notes(notes, setting: liste) == "Pour samedi\n🛒 Liste : 2/2 cochés")
        #expect(Liste.notes(notes, setting: nil) == "Pour samedi")
        #expect(NoteLines.visible(notes) == "Pour samedi")
        #expect(liste.toutCoché && !Liste().toutCoché)
    }

    /// La montre coche les œufs pendant que l'iPhone coche le pain : les deux coches restent.
    @Test func cochesCroisees() {
        let base = Liste(articles: [Self.article("o", "Œufs"), Self.article("p", "Pain")])
        var iphone = base
        iphone.articles[1].coche = true
        iphone.articles[1].maj = "2026-10-16T20:01:00Z"
        var montre = base
        montre.articles[0].coche = true
        montre.articles[0].maj = "2026-10-16T20:02:00Z"
        let f = Liste.fusion(locale: iphone, serveur: montre, base: base)
        #expect(f?.articles.map(\.coche) == [true, true])
        #expect(Liste.fusion(locale: montre, serveur: iphone, base: base)?.articles.map(\.coche) == [true, true])
    }

    @Test func memeArticleLePlusRecentGagne() {
        let base = Liste(articles: [Self.article("o", "Œufs")])
        var a = base
        a.articles[0].coche = true
        a.articles[0].maj = "2026-10-16T20:05:00Z"
        var b = base
        b.articles[0].texte = "Œufs bio"
        b.articles[0].maj = "2026-10-16T20:03:00Z"
        #expect(Liste.fusion(locale: b, serveur: a, base: base)?.articles == a.articles)
    }

    @Test func ajoutsDesDeuxCotes() {
        let base = Liste(articles: [Self.article("o", "Œufs")])
        var a = base
        a.articles.append(Self.article("l", "Lait"))
        var b = base
        b.articles.append(Self.article("p", "Pain"))
        let f = Liste.fusion(locale: a, serveur: b, base: base)
        // L'article venu d'en face se place après son voisin d'avant (Œufs).
        #expect(f?.articles.map(\.texte) == ["Œufs", "Pain", "Lait"])
    }

    @Test func suppressions() {
        let base = Liste(articles: [Self.article("o", "Œufs"), Self.article("p", "Pain"), Self.article("l", "Lait")])
        // Retiré ici, intact en face : reste retiré.
        var ici = base
        ici.articles.remove(at: 1)
        #expect(Liste.fusion(locale: ici, serveur: base, base: base)?.articles.map(\.id) == ["o", "l"])
        // Retiré en face, intact ici : retiré aussi.
        #expect(Liste.fusion(locale: base, serveur: ici, base: base)?.articles.map(\.id) == ["o", "l"])
        // Retiré ici, coché en face : la modification gagne, l'article revient à sa place.
        var enFace = base
        enFace.articles[1].coche = true
        enFace.articles[1].maj = "2026-10-16T20:10:00Z"
        #expect(Liste.fusion(locale: ici, serveur: enFace, base: base)?.articles.map(\.id) == ["o", "p", "l"])
        // Retiré en face, modifié ici : gardé.
        #expect(Liste.fusion(locale: enFace, serveur: ici, base: base)?.articles.map(\.id) == ["o", "p", "l"])
    }

    /// Hors ligne : sans ancêtre connu (première liste), rien n'est perdu.
    @Test func sansBase() {
        let a = Liste(articles: [Self.article("o", "Œufs")])
        let b = Liste(articles: [Self.article("p", "Pain")])
        #expect(Liste.fusion(locale: a, serveur: b, base: nil)?.articles.count == 2)
        #expect(Liste.fusion(locale: nil, serveur: b, base: nil) == b)
        #expect(Liste.fusion(locale: a, serveur: nil, base: nil) == a)
    }

    @Test func allerRetourParTaskItem() {
        let item = TaskItem(title: "Courses")
        item.liste = Liste(articles: [Self.article("o", "Œufs", coche: true), Self.article("p", "Pain")])
        let tache = TacheHA(item)
        #expect(tache.liste?.articles.count == 2)
        #expect(tache.notes.hasSuffix("🛒 Liste : 1/2 cochés"))
        let autre = TaskItem(title: "")
        tache.apply(to: autre)
        #expect(autre.liste == tache.liste && autre.listeBase == tache.liste)
    }

    /// Conflit sur la tâche entière (`Synchroniseur.fusion`) : liste fusionnée, ligne 🛒 et « Fait » recalculés.
    @Test func fusionDeTache() throws {
        let base = Liste(articles: [Self.article("o", "Œufs"), Self.article("p", "Pain")])
        var locale = TacheHA(titre: "Courses")
        locale.liste = base
        locale.liste?.articles[1].coche = true
        locale.liste?.articles[1].maj = "2026-10-16T20:01:00Z"
        var serveur = TacheHA(titre: "Courses")
        serveur.liste = base
        serveur.liste?.articles[0].coche = true
        serveur.liste?.articles[0].maj = "2026-10-16T20:02:00Z"
        let f = try #require(Liste.fusion(locale: locale, serveur: serveur, base: base))
        #expect(f.liste?.toutCoché == true && f.fait && f.faitLe != nil)
        #expect(f.notes.hasSuffix("🛒 Liste : 2/2 cochés"))
        // Sans liste d'aucun côté : la règle « dernier écrit gagne » du paquet.
        #expect(Liste.fusion(locale: TacheHA(titre: "a"), serveur: TacheHA(titre: "b"), base: nil) == nil)
    }
}

/// Cocher, ajouter, tout coché → Fait (P9-G1).
@MainActor
struct ListeStoreTests {
    @Test func saisieDUnArticle() {
        #expect(TaskStore.article("6 œufs")?.quantite == "6")
        #expect(TaskStore.article("6 œufs")?.texte == "œufs")
        #expect(TaskStore.article("Lait demi-écrémé")?.quantite == nil)
        #expect(TaskStore.article("   ") == nil)
    }

    @Test func toutCocheFaitPuisRouvre() throws {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let item = store.add(title: "Courses", day: nil, minutes: nil)
        store.addArticle("Pain", to: item)
        store.addArticle("2 lait", to: item)
        let liste = try #require(item.liste)
        #expect(liste.articles.map(\.texte) == ["Pain", "lait"] && liste.articles.allSatisfy { $0.maj != nil })
        #expect(store.toggleArticle(id: liste.articles[0].id, of: item) == false)
        #expect(!item.isCompleted)
        #expect(store.toggleArticle(id: liste.articles[1].id, of: item) == true)
        #expect(item.isCompleted)
        #expect(TacheHA(item).notes.hasSuffix("🛒 Liste : 2/2 cochés"))
        // Décocher rouvre ; ajouter à une liste faite la rouvre aussi.
        store.toggleArticle(id: liste.articles[1].id, of: item)
        #expect(!item.isCompleted)
        store.toggleArticle(id: liste.articles[1].id, of: item)
        #expect(item.isCompleted)
        store.addArticle("Beurre", to: item)
        #expect(!item.isCompleted && item.liste?.articles.count == 3)
        store.removeArticles(at: [0], of: item)
        #expect(item.liste?.articles.map(\.texte) == ["lait", "Beurre"])
    }
}
