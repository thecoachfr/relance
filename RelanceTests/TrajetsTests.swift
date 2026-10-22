import Foundation
import Testing
@testable import Relance

/// Arrêts relevés pour l'historique des trajets (P9-M2).
struct TrajetsTests {
    let arrivee = Date(timeIntervalSince1970: 1_792_650_000)

    func visite(depart: Date = .distantFuture, lat: Double = 48.853) -> VisiteTrajet {
        VisiteTrajet(arrivee: arrivee, depart: depart, lat: lat, lon: 2.357, precision: 64.27)!
    }

    @Test func visiteIOS() {
        let v = visite()
        #expect(v.arrivee == 1_792_650_000 && v.depart == nil && v.precision == 64.3)
        #expect(visite(depart: arrivee.addingTimeInterval(1800)).depart == 1_792_651_800)
        // Arrivée inconnue (visite commencée avant le suivi) : rien à garder.
        #expect(VisiteTrajet(arrivee: .distantPast, depart: .now, lat: 48.85, lon: 2.35, precision: 50) == nil)
    }

    @Test func departCompleteLArrivee() {
        var file = TrajetsFile.ajout([], visite())
        file = TrajetsFile.ajout(file, visite(depart: arrivee.addingTimeInterval(600)))
        #expect(file.count == 1 && file[0].depart == 1_792_650_600)
        // Une version sans départ (rejouée) ne l'efface pas.
        file = TrajetsFile.ajout(file, visite(lat: 48.854))
        #expect(file.count == 1 && file[0].depart == 1_792_650_600 && file[0].lat == 48.854)
    }

    @Test func envoiGardeLesMisesAJour() {
        let envoyes = TrajetsFile.ajout([], visite())
        // Départ arrivé pendant l'envoi : il reste à envoyer.
        let pendant = TrajetsFile.ajout(envoyes, visite(depart: arrivee.addingTimeInterval(600)))
        #expect(TrajetsFile.apresEnvoi(pendant, envoyes: envoyes).count == 1)
        #expect(TrajetsFile.apresEnvoi(envoyes, envoyes: envoyes).isEmpty)
    }

    @Test func fileBornee() {
        var file: [VisiteTrajet] = []
        for i in 0..<(TrajetsFile.maximum + 5) {
            file = TrajetsFile.ajout(file, VisiteTrajet(arrivee: arrivee.addingTimeInterval(Double(i) * 3600),
                                                        depart: .distantFuture, lat: 48.85, lon: 2.35, precision: 50)!)
        }
        #expect(file.count == TrajetsFile.maximum && file[0].arrivee == 1_792_650_000 + 5 * 3600)
    }
}
