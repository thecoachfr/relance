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
