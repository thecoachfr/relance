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
        // Modifier sur place : la quantité suit la saisie ; vider retire l'article.
        let lait = try #require(item.liste?.articles.first)
        store.editArticle(id: lait.id, saisie: "3 lait entier", of: item)
        #expect(item.liste?.articles.first?.texte == "lait entier" && item.liste?.articles.first?.quantite == "3")
        store.editArticle(id: lait.id, saisie: "  ", of: item)
        #expect(item.liste?.articles.map(\.texte) == ["Beurre"])
    }

    /// Coche venue de la montre (P9-G2) : datée de son geste, ignorée si l'article a changé depuis.
    @Test func cocheDeLaMontre() throws {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let item = store.add(title: "Courses", day: nil, minutes: nil)
        store.addArticle("Pain", to: item, now: Date(timeIntervalSince1970: 100))
        store.addArticle("Lait", to: item, now: Date(timeIntervalSince1970: 100))
        let ids = try #require(item.liste?.articles.map(\.id))
        store.setArticle(id: ids[0], coche: true, of: item, at: Date(timeIntervalSince1970: 200))
        #expect(item.liste?.articles[0].coche == true && !item.isCompleted)
        // Message en retard, plus ancien que la dernière modification : ignoré.
        store.setArticle(id: ids[0], coche: false, of: item, at: Date(timeIntervalSince1970: 150))
        #expect(item.liste?.articles[0].coche == true)
        store.setArticle(id: ids[1], coche: true, of: item, at: Date(timeIntervalSince1970: 300))
        #expect(item.isCompleted)
        let envoye = WatchTask(id: "x", title: "Courses", due: nil, hasTime: false,
                               articles: [WatchArticle(id: "a", texte: "Pain", quantite: "2", coche: false)])
        #expect(WatchLink.decode(WatchLink.encode([envoye])) == [envoye])
    }

    /// Mes lieux (P9-H2) : format dans HA, rattachement automatique et manuel.
    @Test func mesLieux() throws {
        var lieux = MesLieux.parDefaut
        lieux.groupes[0].lieux.append(.init(nom: "Carrefour City", adresse: "1 rue X", lat: 48.8, lon: 2.4))
        // Ancien format, sans domicile : toujours lisible.
        let ancien = try #require(MesLieux(valeur: .objet(["groupes": .liste([])])))
        #expect(ancien.domicile == nil && ancien.groupes.isEmpty)
        lieux.domicile = .init(nom: "Maison", adresse: "1 rue Y, 94140 Alfortville", lat: 48.81, lon: 2.42)
        let maison = MesLieux.contact(try #require(lieux.domicile))
        #expect(maison.name == "Maison" && maison.coordinate?.latitude == 48.81)
        let relu = try #require(MesLieux(valeur: lieux.valeur))
        #expect(relu == lieux && relu.lieu(lieux.groupes[0].lieux[0].id)?.groupe.id == MesLieux.supermarches)

        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let courses = store.add(title: "Courses", day: nil, minutes: nil, category: "Achats")
        #expect(courses.groupesDeLieux.isEmpty)  // pas de liste
        store.addArticle("Pain", to: courses)
        #expect(courses.groupesDeLieux == [MesLieux.supermarches])
        store.toggleArticle(id: try #require(courses.liste?.articles.first?.id), of: courses)
        #expect(courses.groupesDeLieux.isEmpty)  // liste finie (et tâche faite)

        let pharmacie = store.add(title: "Ordonnance", day: nil, minutes: nil)
        store.addAction(.pres(groupe: "pharma", nom: "Pharmacies"), to: pharmacie)
        #expect(pharmacie.groupesDeLieux == ["pharma"])
        let action = try #require(pharmacie.actions.first)
        #expect(action.titre == "Me le rappeler près de : Pharmacies" && !action.auToucher)
    }

    /// Liste de courses sans date (28/10) : pas dans À trier (le magasin la rappelle), une tâche sans date si.
    @Test func listeDeCoursesSansDateHorsDeATrier() {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let courses = store.add(title: "Courses", day: nil, minutes: nil, category: "Achats")
        #expect(courses.needsTriage)  // pas encore de liste
        store.addArticle("Pain", to: courses)
        #expect(!courses.needsTriage && courses.estListeDeCoursesSansDate)
        let valise = store.add(title: "Valise", day: nil, minutes: nil, category: "Perso")
        store.addArticle("Chargeur", to: valise)
        #expect(valise.needsTriage && !valise.estListeDeCoursesSansDate)  // une liste qui n'est pas des courses
    }

    /// Photo de produits (P9-R, 28/10) : notée à lire, articles proposés gardés en cochant ou par « Tout garder ».
    @Test func photoDeCourses() throws {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let courses = store.add(title: "Courses", day: nil, minutes: nil, category: "Achats")
        let piece = TacheHA.Piece(id: "abc", nom: "Produits 1.jpg", type: "image/jpeg", taille: 1000, source: "photo")
        store.ajouterPhotosDeCourses([piece], to: courses)
        #expect(courses.pieces.map(\.id) == ["abc"])
        #expect(courses.liste?.photosALire == 1)
        // La vigie a lu la photo : deux articles proposés, photo lue.
        var liste = try #require(courses.liste)
        var lu = TacheHA.Liste.Article(texte: "Lessive liquide Skip", source: "photo")
        lu.propose = true
        var lu2 = TacheHA.Liste.Article(texte: "Adoucissant Soupline", source: "photo")
        lu2.propose = true
        liste.articles = [lu, lu2]
        liste.autres["photos"] = .liste([.objet(["piece": .texte("abc"), "lue_le": .texte("2026-10-28T14:00:00Z")])])
        store.setListe(liste, of: courses)
        #expect(courses.liste?.photosALire == 0 && courses.liste?.aDesProposes == true)
        _ = store.toggleArticle(id: lu.id, of: courses)
        #expect(courses.liste?.articles.first?.propose == false)  // cocher, c'est garder
        store.garderProposes(of: courses)
        #expect(courses.liste?.aDesProposes == false)
        // Codage : `propose` est un champ de l'article, gardé tel quel.
        let donnees = try JSONEncoder().encode(lu)
        #expect(String(decoding: donnees, as: UTF8.self).contains("\"propose\":true"))
    }

    /// Conflit entre appareils (P9-R) : une photo lue d'un côté l'est des deux (sinon elle serait relue).
    @Test func fusionDesPhotos() {
        var ici = TacheHA.Liste()
        ici.ajouterPhoto(piece: "abc", le: "2026-10-28T14:00:00Z")
        ici.ajouterPhoto(piece: "def", le: "2026-10-28T14:01:00Z")
        var enFace = TacheHA.Liste()
        enFace.autres["photos"] = .liste([.objet(["piece": .texte("abc"), "lue_le": .texte("2026-10-28T14:02:00Z")]),
                                          .objet(["piece": .texte("ghi"), "a_lire": .booleen(true)])])
        let liste = TacheHA.Liste.fusion(locale: ici, serveur: enFace, base: nil)
        #expect(liste?.photosALire == 2)  // def (ici) et ghi (en face) ; abc lue
    }

    /// Magasin d'une liste (P9-Q, 28/10) : « Courses a Leroy merlin » prévenait près des supermarchés.
    @Test func magasinDeLaListe() throws {
        var lieux = MesLieux.parDefaut
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let leroy = store.add(title: "Courses a Leroy merlin", day: nil, minutes: nil, category: "Achats")
        store.addArticle("Gouttière", to: leroy)
        // Enseigne connue sans groupe : aucun rappel (surtout pas les supermarchés), la fiche propose de le créer.
        #expect(lieux.magasin(titre: leroy.title, actions: leroy.actions) == .enseigneSansGroupe("Leroy Merlin"))
        #expect(leroy.groupesDeLieux(lieux).isEmpty)
        // Groupe créé : lui seul, accents et casse ignorés.
        lieux.groupes.append(.init(id: "lm", nom: "Leroy Merlin"))
        #expect(leroy.groupesDeLieux(lieux) == ["lm"])
        #expect(MesLieux.nomme("Brico Dépôt", dans: "achats BRICO DEPOT samedi"))
        #expect(!MesLieux.nomme("Lidl", dans: "Courses Lidlx"))
        // Choix explicite : il fait foi, et lui seul (avant : Supermarchés en plus).
        store.addAction(.pres(groupe: "brico", nom: "Bricolage"), to: leroy)
        #expect(leroy.groupesDeLieux(lieux) == ["brico"])
        // Sans enseigne : Supermarchés, comme avant.
        let courses = store.add(title: "Courses de la semaine", day: nil, minutes: nil, category: "Achats")
        store.addArticle("Pain", to: courses)
        #expect(courses.groupesDeLieux(lieux) == [MesLieux.supermarches])
    }

    /// Liste du jour sans heure rattachée aux magasins : dans À faire, pas dans À trier, pas de « À quelle heure ? »
    /// (17/10, remarque d'Alexandre : elle passait dans À trier).
    @Test func listeDuJourSansHeureResteDansAFaire() {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let courses = store.add(title: "Courses", day: .now, minutes: nil, category: "Achats")
        #expect(courses.needsTriage)  // pas encore de liste : l'heure manque
        store.addArticle("Pain", to: courses)
        #expect(!courses.needsTriage && courses.plannable().atMyPlaces)
        let sansDate = store.add(title: "Courses plus tard", day: nil, minutes: nil, category: "Achats")
        store.addArticle("Lait", to: sansDate)
        // Sans date : plus à trier depuis le 28/10 (le magasin la rappelle ; elle était bloquée dans À trier).
        #expect(!sansDate.needsTriage)
    }

    // MARK: - Liste de courses unique (P9-U)

    /// Le champ `magasins` et `permanente` passent par HA ; une liste ordinaire n'écrit rien de plus.
    @Test func magasinsDansLeFormat() throws {
        var liste = TacheHA.Liste(articles: [.init(id: "a", texte: "Lessive", magasins: ["supermarches", "droguerie"]),
                                             .init(id: "b", texte: "Pain")])
        liste.permanente = true
        let relue = try JSONDecoder().decode(TacheHA.Liste.self, from: JSONEncoder().encode(liste))
        #expect(relue == liste && relue.permanente && relue.articles[0].magasins.count == 2)
        let brut = String(decoding: try JSONEncoder().encode(TacheHA.Liste(articles: [.init(id: "b", texte: "Pain")])), as: UTF8.self)
        #expect(!brut.contains("magasins") && !brut.contains("permanente"))
    }

    /// Une liste permanente ne finit jamais, même tout cochée ou par « Fait ».
    @Test func listeUniqueJamaisFaite() throws {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let courses = store.listeDeCourses()
        #expect(courses.localID == TacheHA.Liste.idCourses && courses.category == "Achats" && courses.liste?.permanente == true)
        #expect(store.listeDeCourses().localID == courses.localID)
        store.addArticle("Pain", to: courses)
        let pain = try #require(courses.liste?.articles.first)
        #expect(store.toggleArticle(id: pain.id, of: courses) == false)
        #expect(!courses.isCompleted && courses.liste?.toutCoché == false)
        store.complete(courses)
        #expect(!courses.isCompleted)
        #expect(!courses.needsTriage)
        // Mise à la corbeille : elle revient au lieu d'être recréée à côté.
        courses.isTrashed = true
        #expect(store.listeDeCourses().localID == courses.localID && !courses.isTrashed)
    }

    /// Un article pris reste 24 h, on peut l'annuler, puis il est retiré ; un article à prendre reste.
    @Test func articlesPrisRetiresApres24h() throws {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let courses = store.listeDeCourses()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.addArticle("Pain", to: courses, now: t0)
        store.addArticle("Lait", to: courses, now: t0)
        let pain = try #require(courses.liste?.articles.first)
        store.toggleArticle(id: pain.id, of: courses, now: t0)
        store.retirerArticlesPris(now: t0.addingTimeInterval(23 * 3600))
        #expect(courses.liste?.articles.count == 2)
        store.retirerArticlesPris(now: t0.addingTimeInterval(24 * 3600))
        #expect(courses.liste?.articles.map(\.texte) == ["Lait"])
        // Sans date, un article coché ne reste pas pour toujours.
        let sansDate = TacheHA.Liste(articles: [.init(id: "x", texte: "Beurre", coche: true)])
        #expect(sansDate.sansArticlesPris(now: t0).articles.isEmpty)
        // Une liste ordinaire n'est pas touchée.
        let autre = store.add(title: "Valise", day: nil, minutes: nil)
        store.addArticle("Chaussettes", to: autre, now: t0)
        store.toggleArticle(id: try #require(autre.liste?.articles.first?.id), of: autre, now: t0)
        store.retirerArticlesPris(now: t0.addingTimeInterval(48 * 3600))
        #expect(autre.liste?.articles.count == 1)
    }

    /// Chaque article donne ses magasins : sans choix ou groupe supprimé, Supermarchés.
    @Test func magasinsParArticle() throws {
        let lieux = MesLieux(groupes: [.init(id: MesLieux.supermarches, nom: "Supermarchés"),
                                       .init(id: "droguerie", nom: "Droguerie"), .init(id: "brico", nom: "Bricolage")])
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let courses = store.listeDeCourses()
        #expect(courses.groupesDeLieux(lieux).isEmpty)  // liste vide : aucun rappel
        store.addArticle("Pain", to: courses)
        store.addArticle("Lessive", to: courses)
        store.addArticle("Gouttière", to: courses)
        store.addArticle("Colle", to: courses)
        let articles = try #require(courses.liste?.articles)
        store.setMagasins([MesLieux.supermarches, "droguerie"], ofArticle: articles[1].id, of: courses)
        store.setMagasins(["brico"], ofArticle: articles[2].id, of: courses)
        store.setMagasins(["supprime"], ofArticle: articles[3].id, of: courses)
        #expect(courses.liste?.articles[1].maj != nil)
        // Choix de la vigie repris à la main : même magasin, la marque part (la vigie le retiendra) ; rien : Supermarchés.
        var parClaude = try #require(courses.liste)
        parClaude.articles[0].magasins = ["droguerie"]
        parClaude.articles[0].parClaude = true
        store.setListe(parClaude, of: courses)
        store.setMagasins(["droguerie"], ofArticle: articles[0].id, of: courses)
        #expect(courses.liste?.articles[0].parClaude == false)
        store.setMagasins([], ofArticle: articles[0].id, of: courses)
        #expect(courses.liste?.articles[0].magasins == [MesLieux.supermarches])
        #expect(courses.groupesDeLieux(lieux) == ["brico", "droguerie", MesLieux.supermarches])
        let liste = try #require(courses.liste)
        #expect(lieux.articles(de: liste, dans: "droguerie").map(\.texte) == ["Lessive"])
        #expect(lieux.articles(de: liste, dans: MesLieux.supermarches).map(\.texte) == ["Pain", "Lessive", "Colle"])
        // Pris : le magasin ne l'attend plus.
        store.toggleArticle(id: articles[2].id, of: courses)
        #expect(courses.groupesDeLieux(lieux) == ["droguerie", MesLieux.supermarches])
        // Le titre et l'enseigne ne comptent pas : seuls les articles décident.
        courses.title = "Courses Leroy Merlin"
        #expect(courses.groupesDeLieux(lieux) == ["droguerie", MesLieux.supermarches])
    }

    /// Ce que montre l'écran Courses : magasins proposés, noms, résumé de la ligne d'À faire.
    @Test func ecranCourses() {
        let lieux = MesLieux(groupes: [.init(id: MesLieux.supermarches, nom: "Supermarchés"), .init(id: "dom", nom: "Domicile"),
                                       .init(id: "t", nom: "Travail"), .init(id: "drog", nom: "Droguerie")])
        #expect(lieux.groupesMagasins.map(\.id) == [MesLieux.supermarches, "drog"])
        let liste = TacheHA.Liste(articles: [.init(id: "a", texte: "Lessive", magasins: ["drog", MesLieux.supermarches]),
                                             .init(id: "b", texte: "Pain"), .init(id: "c", texte: "Sel", coche: true)])
        #expect(lieux.noms(de: liste.articles[0]) == "Droguerie, Supermarchés" && lieux.noms(de: liste.articles[1]) == "Supermarchés")
        #expect(lieux.resume(de: liste) == "2 à prendre · Droguerie 1 · Supermarchés 2")
        #expect(lieux.resume(de: TacheHA.Liste()) == "Rien à prendre")
        #expect(MesLieux().nom(MesLieux.supermarches) == "Supermarchés")
        // Article ajouté pendant un filtre : il va à ce magasin.
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let courses = store.listeDeCourses()
        store.addArticle("Javel", to: courses, magasins: ["drog"])
        #expect(courses.liste?.articles.first?.magasins == ["drog"])
    }

    /// Fusion : choix du magasin et coche sur deux appareils, un article retiré des deux côtés sans conflit.
    @Test func fusionDeLaListeUnique() throws {
        var base = TacheHA.Liste(articles: [
            .init(id: "a", texte: "Lessive", maj: "2026-11-04T10:00:00Z"),
            .init(id: "b", texte: "Pain", coche: true, maj: "2026-11-03T10:00:00Z"),
        ])
        base.permanente = true
        var ici = base, enFace = base
        ici.articles[0].magasins = ["droguerie"]
        ici.articles[0].maj = "2026-11-04T11:00:00Z"
        ici.articles.remove(at: 1)  // article pris retiré ici, inchangé en face
        enFace.articles.append(.init(id: "c", texte: "Huile", maj: "2026-11-04T11:30:00Z"))
        let fusion = try #require(TacheHA.Liste.fusion(locale: ici, serveur: enFace, base: base))
        #expect(fusion.permanente && fusion.articles.map(\.id) == ["a", "c"])
        #expect(fusion.articles[0].magasins == ["droguerie"])
        // Décoché en face pendant le retrait ici : l'annulation gagne, l'article revient.
        var annule = base
        annule.articles[1].coche = false
        annule.articles[1].maj = "2026-11-04T12:00:00Z"
        #expect(TacheHA.Liste.fusion(locale: ici, serveur: annule, base: base)?.articles.map(\.id) == ["a", "b"])
    }
}
