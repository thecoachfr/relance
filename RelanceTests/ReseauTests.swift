import Foundation
import Testing
@testable import Relance

/// Nouvel essai vers Google : seulement pour un échec passager, jamais pour un ajout déjà reçu (doublon).
struct ReseauTests {
    @Test func attenteCroissanteSurErreurServeur() {
        #expect(Reseau.attente(tentative: 1, statut: 503, erreur: nil, rejouable: true) == .seconds(1))
        #expect(Reseau.attente(tentative: 2, statut: 503, erreur: nil, rejouable: true) == .seconds(2))
        #expect(Reseau.attente(tentative: 3, statut: 503, erreur: nil, rejouable: true) == nil)   // 3 essais au plus
    }

    @Test func pasDeNouvelEssaiPourUnAjoutSaufSur429() {
        #expect(Reseau.attente(tentative: 1, statut: 500, erreur: nil, rejouable: false) == nil)
        #expect(Reseau.attente(tentative: 1, statut: nil, erreur: .timedOut, rejouable: false) == nil)
        #expect(Reseau.attente(tentative: 1, statut: 429, erreur: nil, rejouable: false) == .seconds(1))
    }

    @Test func retryAfterRespecteEtPlafonne() {
        #expect(Reseau.attente(tentative: 1, statut: 429, erreur: nil, rejouable: true, retryAfter: "3") == .seconds(3))
        #expect(Reseau.attente(tentative: 1, statut: 429, erreur: nil, rejouable: true, retryAfter: "120") == .seconds(10))
    }

    @Test(arguments: [200, 400, 401, 403, 404])
    func pasDeNouvelEssaiHorsEchecPassager(statut: Int) {
        #expect(Reseau.attente(tentative: 1, statut: statut, erreur: nil, rejouable: true) == nil)
    }

    @Test func horsLignePasDeNouvelEssaiImmediat() {
        #expect(Reseau.attente(tentative: 1, statut: nil, erreur: .notConnectedToInternet, rejouable: true) == nil)
        #expect(Reseau.attente(tentative: 1, statut: nil, erreur: .networkConnectionLost, rejouable: true) == .seconds(1))
    }
}

/// Home Assistant (23/10) : quels appels du mémo peuvent être renvoyés si la réponse s'est perdue.
struct ReseauHATests {
    @Test func ajoutAuMemoNonRejouable() {
        #expect(!MemoHA.rejouable("add_item"))
        #expect(MemoHA.rejouable("get_items") && MemoHA.rejouable("update_item"))
    }

    @Test func demandeDeTriPasRenvoyeeSiElleAPuPartir() {
        // Tri, lien sur la TV : `rejouable: false`. Réponse perdue ou 5xx : pas de second envoi ; 429 : rien n'a été fait.
        #expect(Reseau.attente(tentative: 1, statut: nil, erreur: .timedOut, rejouable: false) == nil)
        #expect(Reseau.attente(tentative: 1, statut: 502, erreur: nil, rejouable: false) == nil)
        #expect(Reseau.attente(tentative: 1, statut: nil, erreur: .timedOut, rejouable: true) == .seconds(1))
    }

    @Test func delaiCourt() {
        #expect(Reseau.session.configuration.timeoutIntervalForRequest == 15)
    }
}

/// Après un envoi raté en arrière-plan (tracé précis, 11/11) : attente croissante avant le nouvel essai.
struct AttenteApresEchecTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func pasDAttenteSansEchec() {
        #expect(!AttenteApresEchec().doitAttendre(a: t0))
    }

    @Test func attenteCroissantePlafonnee() {
        #expect(AttenteApresEchec.pause(apres: 1) == 120)
        #expect(AttenteApresEchec.pause(apres: 2) == 240)
        #expect(AttenteApresEchec.pause(apres: 4) == 960)
        #expect(AttenteApresEchec.pause(apres: 5) == 1800)
        #expect(AttenteApresEchec.pause(apres: 50) == 1800)
    }

    @Test func echecPuisReussite() {
        var a = AttenteApresEchec()
        a.echec(a: t0)
        #expect(a.doitAttendre(a: t0 + 60))      // 23 points en 5 min : plus 23 essais
        #expect(!a.doitAttendre(a: t0 + 120))
        a.echec(a: t0 + 120)
        #expect(a.doitAttendre(a: t0 + 120 + 239))
        #expect(!a.doitAttendre(a: t0 + 120 + 240))
        a.reussite()
        #expect(a == AttenteApresEchec())
    }

    @Test func gardeeEnJSON() throws {
        var a = AttenteApresEchec()
        a.echec(a: t0)
        let relue = try JSONDecoder().decode(AttenteApresEchec.self, from: JSONEncoder().encode(a))
        #expect(relue == a)
    }
}
