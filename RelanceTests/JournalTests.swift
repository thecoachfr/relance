import Foundation
import Testing
@testable import Relance

/// Journal des erreurs : un échec répété ne remplit pas le journal, `essayer` se comporte comme `try?` en laissant une trace.
/// Chaque test a son propre registre : l'app qui héberge les tests écrit dans celui de l'App Group pendant ce temps.
struct JournalTests {
    struct Panne: LocalizedError { var errorDescription: String? { "panne" } }

    let registre = Journal.Registre(suite: "tests-journal-\(UUID().uuidString)")

    @Test func echecRepeteRegroupe() {
        Journal.echec(.synchro, "Synchro Home Assistant", Panne(), dans: registre)
        Journal.echec(.synchro, "Synchro Home Assistant", Panne(), dans: registre)
        Journal.echec(.reseau, "Envoi des trajets", dans: registre)
        let entrees = registre.recentes()
        #expect(entrees.count == 2)
        #expect(entrees[0].texte == "Envoi des trajets")
        #expect(entrees[1].fois == 2)
        #expect(entrees[1].texte.hasPrefix("Synchro Home Assistant : "))
        #expect(entrees[1].texte.hasSuffix("panne"))
        registre.effacer()
    }

    @Test func plafondDeTrenteEntrees() {
        for i in 0..<40 { Journal.echec(.stockage, "Échec \(i)", dans: registre) }
        let entrees = registre.recentes()
        #expect(entrees.count == 30)
        #expect(entrees.first?.texte == "Échec 39")
        registre.effacer()
    }

    @Test func essayerRenvoieNilEtNote() {
        let ok = Journal.essayer(.stockage, "Lecture", dans: registre) { 42 }
        let rate: Int? = Journal.essayer(.stockage, "Écriture", dans: registre) { throw Panne() }
        #expect(ok == 42)
        #expect(rate == nil)
        #expect(registre.recentes().map(\.texte) == ["Écriture : \(Journal.decrire(Panne()))"])
        registre.effacer()
    }

    @Test func annulationNonNotee() async {
        let r: Int? = await Journal.essayer(.reseau, "Requête annulée", dans: registre) { throw CancellationError() }
        #expect(r == nil)
        #expect(registre.recentes().isEmpty)
    }

    @Test func reponseHTTP() throws {
        let url = try #require(URL(string: "https://exemple.test"))
        let ok = try #require(HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil))
        let refus = try #require(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
        #expect(Journal.reponseOK(ok, .reseau, "Inscription aux push", dans: registre))
        #expect(!Journal.reponseOK(refus, .reseau, "Inscription aux push", dans: registre))
        #expect(registre.recentes().map(\.texte) == ["Inscription aux push : HTTP 401"])
        registre.effacer()
    }
}
