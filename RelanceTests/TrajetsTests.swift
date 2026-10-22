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

/// Écran « Mes trajets » (P9-M3).
struct TrajetsCarteTests {
    @Test func segmentsCoupesAuxTrous() {
        let t0 = 1_792_650_000.0
        let points: [[Double]] = [
            [t0, 48.85, 2.35], [t0 + 10, 48.8501, 2.35], [t0 + 20, 48.8502, 2.35],
            [t0 + 1000, 48.8503, 2.35], [t0 + 1010, 48.8504, 2.35],      // trou de 16 min : nouveau morceau
            [t0 + 1020, 48.90, 2.35],                                    // saut de 5,5 km : point isolé, écarté
        ]
        let s = JourTrajets.segments(points)
        #expect(s.map(\.count) == [3, 2])
    }

    @Test func heuresDUnArret() throws {
        let data = #"{"arrivee": 1792650000, "depart": 1792655100, "lat": 48.85, "lon": 2.35}"#.data(using: .utf8)!
        let arret = try JSONDecoder().decode(ArretTrajet.self, from: data)
        #expect(TrajetsCarteView.heures(arret).hasSuffix("· 1 h 25"))
        let ouvert = ArretTrajet(arrivee: 1_792_650_000, depart: nil, lat: 48.85, lon: 2.35)
        #expect(TrajetsCarteView.heures(ouvert).hasPrefix("depuis "))
    }

    @Test func jourDeParis() {
        let d = TrajetsService.date(jour: "2026-10-22")!
        let c = TrajetsService.calendrier.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(c.year == 2026 && c.month == 10 && c.day == 22 && c.hour == 12)
        #expect(TrajetsService.date(jour: "n'importe quoi") == nil)
    }
}
