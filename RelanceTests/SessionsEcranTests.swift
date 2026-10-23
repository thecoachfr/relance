import Foundation
import Testing
@testable import Relance

/// Sessions à l'écran de la montre (C1) : seul un arrêt pendant une session ouverte compte, le pic est suivi,
/// les écritures sont espacées. Code pur partagé (Shared/Divers), testé côté iPhone.
struct SessionsEcranTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sessionFermeeNormalementNonComptee() {
        var j = JournalSessions()
        let premiere = j.ouvrir(a: t0, mo: 20)
        #expect(premiere == nil)
        j.mesurer(a: t0 + 10, mo: 25)
        j.fermer(a: t0 + 15, mo: 22)
        #expect(!j.estOuverte)
        let seconde = j.ouvrir(a: t0 + 600, mo: 21)
        #expect(seconde == nil)
        #expect(j.bilan(depuis: t0).arrets == 0)
        #expect(j.sessions[0].picMo == 25)
        #expect(j.sessions[0].duree == 15)
    }

    @Test func sessionResteeOuverteComptee() throws {
        var j = JournalSessions()
        j.ouvrir(a: t0, mo: 20)
        j.mesurer(a: t0 + 130, mo: 37.6)
        // L'app est arrêtée à l'écran : pas de fermeture. Au lancement suivant :
        let ouverture = j.ouvrir(a: t0 + 900, mo: 19)
        let arretee = try #require(ouverture)
        #expect(arretee.interrompue)
        #expect(arretee.messageArret == "Arrêt inattendu à l'écran (pic 38 Mo, durée 2 min 10 s)")
        #expect(j.bilan(depuis: t0).arrets == 1)
        #expect(j.arrets(depuis: t0).count == 1)
        // La nouvelle session est bien ouverte, et ne sera pas comptée deux fois.
        j.fermer(a: t0 + 910, mo: 19)
        let suivante = j.ouvrir(a: t0 + 1000, mo: 19)
        #expect(suivante == nil)
        #expect(j.bilan(depuis: t0).arrets == 1)
    }

    @Test func mesureHorsSessionIgnoree() {
        var j = JournalSessions()
        let pic = j.mesurer(a: t0, mo: 50)
        #expect(!pic)
        j.fermer(a: t0, mo: 50)
        #expect(j.sessions.isEmpty)
    }

    @Test func bilanParPeriodeEtPurge() {
        var j = JournalSessions()
        j.ouvrir(a: t0, mo: 40); j.fermer(a: t0 + 60, mo: 40)
        j.ouvrir(a: t0 + 3 * 86_400, mo: 30); j.fermer(a: t0 + 3 * 86_400 + 30, mo: 31)
        let recent = j.bilan(depuis: t0 + 86_400)
        #expect(recent.sessions == 1)
        #expect(recent.picMo == 31)
        #expect(j.bilan(depuis: t0).picMo == 40)
        // Plus de 8 jours après : la première session est oubliée.
        j.ouvrir(a: t0 + 9 * 86_400, mo: 20)
        #expect(j.sessions.count == 2)
        #expect(j.sessions.first?.debutMo == 30)
    }

    @Test func cadenceEcriture() {
        var c = CadenceEcriture()
        c.ecrit(a: t0, pic: 20)
        let reponses = [c.doitEcrire(a: t0 + 10, pic: 20.5),
                        c.doitEcrire(a: t0 + 20, pic: 21.2),   // pic monté de 1 Mo
                        c.doitEcrire(a: t0 + 30, pic: 21.2),
                        c.doitEcrire(a: t0 + 50, pic: 21.2)]   // 30 s depuis la dernière écriture
        #expect(reponses == [false, true, false, true])
    }

    @Test func texteDuree() {
        #expect(SessionEcran.texteDuree(42) == "42 s")
        #expect(SessionEcran.texteDuree(120) == "2 min")
        #expect(SessionEcran.texteDuree(3_725) == "1 h 2 min")
    }

    @Test func registreInjectable() {
        let registre = RegistreSessions(suite: "tests-sessions-\(UUID().uuidString)")
        var j = JournalSessions()
        j.ouvrir(a: t0, mo: 20)
        registre.enregistrer(j)
        #expect(registre.charger() == j)
        registre.effacer()
        #expect(registre.charger().sessions.isEmpty)
    }

    @Test func empreinteMesuree() {
        #expect(Empreinte.megaoctets() > 1)
    }
}
