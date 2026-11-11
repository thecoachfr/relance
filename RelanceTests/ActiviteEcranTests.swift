import DonneesHA
import Foundation
import Testing
@testable import Relance

/// Écran ou action au moment d'un pic de mémoire (11/11) : libellés fixes, pic relevé en fin d'action.
struct ActiviteEcranTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func texteDuContexte() {
        #expect(ActiviteEcran.texte([]) == nil)
        #expect(ActiviteEcran.texte([(1, "À faire"), (2, "Fiche d'une tâche"), (3, "Lecture"), (4, "Lecture")])
                == "À faire › Fiche d'une tâche › Lecture")
    }

    @Test func picReleveEnFinDAction() {
        let jeton = ActiviteEcran.debut(.scan)
        #expect(ActiviteEcran.contexte?.contains("Scan de document") == true)
        ActiviteEcran.fin(jeton, mo: 1e9)   // plus que tout autre test qui tournerait en même temps
        let pic = ActiviteEcran.prendrePic()
        #expect(pic?.mo == 1e9)
        #expect(pic?.contexte.contains("Scan de document") == true)
        #expect(ActiviteEcran.contexte?.contains("Scan de document") != true)
    }

    @Test func picDeSessionGardeSonContexte() {
        var j = JournalSessions()
        j.ouvrir(a: t0, mo: 60, contexte: "À faire")
        j.mesurer(a: t0 + 10, mo: 640, contexte: "À faire › Fiche d'une tâche › Scan de document")
        j.mesurer(a: t0 + 20, mo: 200, contexte: "À faire")   // plus bas : le contexte du pic reste
        #expect(j.sessions[0].picContexte == "À faire › Fiche d'une tâche › Scan de document")
        #expect(j.bilan(depuis: t0).picContexte == "À faire › Fiche d'une tâche › Scan de document")
        #expect(j.gros(depuis: t0, seuil: 250).count == 1)
        // Un arrêt à l'écran dit aussi où était le pic.
        let arretee = j.ouvrir(a: t0 + 900, mo: 50)
        #expect(arretee?.messageArret == "Arrêt inattendu à l'écran (pic 640 Mo, durée 20 s, À faire › Fiche d'une tâche › Scan de document)")
    }

    @Test func anciennesSessionsRelues() throws {
        // Sessions gardées avant le 11/11, sans `picContexte`.
        let json = #"{"sessions":[{"debut":0,"derniereMesure":10,"debutMo":40,"picMo":90,"interrompue":false}]}"#
        let j = try JSONDecoder().decode(JournalSessions.self, from: Data(json.utf8))
        #expect(j.sessions[0].picContexte == nil)
    }

    @Test func erreurHALisible() {
        let e: any Error = ErreurHA.injoignable("Une erreur SSL s'est produite")
        #expect(Journal.decrire(e).contains("Home Assistant injoignable : Une erreur SSL s'est produite"))
        #expect(!Journal.decrire(ErreurHA.nonAutorise).hasSuffix("error 1.)"))
    }
}
