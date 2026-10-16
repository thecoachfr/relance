import DonneesHA
import Foundation
import Testing
@testable import Relance

/// Actions des tâches (P9-D1) : format dans HA, champs inconnus conservés, aller-retour par la tâche locale.
@MainActor
struct ActionsTests {
    let json = """
        {"v": 2, "titre": "Spaceships", "fait": false, "notes": "🎧 À écouter",
         "envie": {"type": "ecouter", "lien": "https://open.spotify.com/track/A1",
                   "playlist": {"statut": "ok", "ajoute_le": "2026-10-16", "ajoutes": 1}},
         "actions": [{"id": "a1", "type": "sur_tv", "executant": "appareil", "declencheur": {"quand": "toucher"},
                      "params": {"lien": "https://open.spotify.com/track/A1"}, "etat": "a_faire", "futur": 3},
                     {"type": "sans id"}],
         "champ_futur": {"x": 1}}
        """

    @Test func decodeEtGardeLesInconnus() throws {
        let t = try JSONDecoder().decode(TacheHA.self, from: Data(json.utf8))
        // L'action mal formée (sans id) est ignorée, l'autre gardée avec son champ inconnu.
        #expect(t.actions.count == 1)
        #expect(t.actions[0].type == "sur_tv")
        #expect(t.actions[0].lien?.absoluteString == "https://open.spotify.com/track/A1")
        #expect(t.actions[0].autres["futur"] == .entier(3))
        #expect(t.autres["champ_futur"] == .objet(["x": .entier(1)]))
        // Réencodée : rien de perdu.
        let back = try JSONDecoder().decode([String: JSONValeur].self, from: JSONEncoder().encode(t))
        #expect(back["champ_futur"] == .objet(["x": .entier(1)]))
        guard case .liste(let actions)? = back["actions"], case .objet(let a)? = actions.first else {
            Issue.record("actions absentes"); return
        }
        #expect(a["futur"] == .entier(3))
        #expect(a["etat"] == .texte("a_faire"))
        #expect(back["v"] == .entier(2))
    }

    /// Une modification sur l'iPhone ne doit plus effacer les champs écrits par d'autres (actions, champ futur).
    @Test func allerRetourParLaTacheLocale() throws {
        let t = try JSONDecoder().decode(TacheHA.self, from: Data(json.utf8))
        let item = TaskItem(title: "")
        t.apply(to: item)
        #expect(item.actions.map(\.id) == ["a1"])
        item.title = "Spaceships (renommé)"
        let renvoyee = TacheHA(item)
        #expect(renvoyee.actions == t.actions)
        #expect(renvoyee.autres["champ_futur"] == .objet(["x": .entier(1)]))
        #expect(renvoyee.titre == "Spaceships (renommé)")
    }

    @Test func ajoutRetraitEtat() {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let item = store.add(title: "Dune", day: nil, minutes: nil, notes: "🎬 À regarder")
        let lien = URL(string: "https://www.netflix.com/title/1")!
        let tv = TacheHA.Action.surAppareil(TacheHA.Action.surTV, lien: lien)
        store.addAction(tv, to: item)
        store.addAction(.surAppareil(TacheHA.Action.ouvrirLien, lien: lien), to: item)
        #expect(item.actions.map(\.type) == ["sur_tv", "ouvrir_lien"])
        #expect(item.isDirty)
        store.markAction(id: tv.id, of: item, etat: "echec", resultat: "TV injoignable", now: Date(timeIntervalSince1970: 0))
        #expect(item.actions[0].etat == "echec")
        #expect(item.actions[0].etatTexte.hasSuffix("TV injoignable"))
        #expect(item.actions[0].maj == "1970-01-01T00:00:00Z")
        store.removeAction(id: tv.id, from: item)
        #expect(item.actions.map(\.type) == ["ouvrir_lien"])
        #expect(TacheHA(item).actions.count == 1)
    }

    @Test func notePlaylist() throws {
        let t = try JSONDecoder().decode(TacheHA.self, from: Data(json.utf8))
        let note = PlaylistNote(t.envie)
        #expect(note?.ok == true)
        #expect(note?.texte == "Ajoutée le 16/10 (1 titre)")
        #expect(PlaylistNote(TacheHA.Envie(type: "ecouter")) == nil)
    }

    /// Recettes de `config:recettes` telles que la vigie les crée ; seul `active` change, le reste est gardé.
    @Test func recettes() throws {
        let json = """
            {"recettes": [{"id": "spotify-playlist", "nom": "Envie À écouter avec un lien Spotify → playlist « À écouter »",
              "active": true, "si": {"envie_type": "ecouter", "hote": "spotify.com"},
              "alors": {"type": "playlist_spotify", "executant": "ha", "declencheur": {"quand": "creation"}}},
             {"id": "tva-micro", "nom": "TVA", "active": false, "si": {"mot": "TVA", "tag": "Micro"},
              "alors": {"type": "preparer", "executant": "routine"}, "futur": 1}]}
            """
        var liste = Recette.liste(try JSONDecoder().decode(JSONValeur.self, from: Data(json.utf8)))
        #expect(liste.map(\.id) == ["spotify-playlist", "tva-micro"])
        #expect(liste[0].active && !liste[1].active)
        #expect(liste[0].conditions == "Envie À écouter · lien spotify.com")
        #expect(liste[1].conditions == "tag Micro · « TVA » dans le titre")
        #expect(liste[1].executant == "par une routine Claude")
        liste[1].active = true
        guard case .objet(let o) = Recette.config(liste), case .liste(let l)? = o["recettes"], case .objet(let tva) = l[1] else {
            Issue.record("forme"); return
        }
        #expect(tva["active"] == .booleen(true))
        #expect(tva["futur"] == .entier(1))
    }

    /// « Me le rappeler à la maison » (P9-F2) : exécutée par la vigie, reste « à faire » et note le dernier rappel.
    @Test func rappelMaison() {
        var a = TacheHA.Action.aLaMaison()
        #expect(a.type == "rappel_maison" && a.executant == "ha" && !a.auToucher)
        #expect(a.declencheur == .objet(["quand": .texte("presence")]))
        #expect(a.etatTexte == "En rentrant à la maison")
        a.resultat = "Rappelé le 16/10 à 21:10"
        #expect(a.etatTexte == "En rentrant à la maison · Rappelé le 16/10 à 21:10")
    }

    @Test func rappelPiece() {
        let a = TacheHA.Action.dans("Chambre")
        #expect(a.type == "rappel_piece" && a.piece == "Chambre" && !a.auToucher)
        #expect(a.titre == "Me le rappeler dans : Chambre")
        #expect(a.etatTexte == "En entrant dans : Chambre")
    }
}
