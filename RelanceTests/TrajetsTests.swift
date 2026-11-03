import CoreLocation
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

/// Tracé précis (P9-M4) : un point gardé tous les 50 m à pied, 100 m au-delà de 30 km/h, jamais s'il est imprécis.
struct TraceTests {
    private func position(_ lat: Double, _ lon: Double, precision: Double = 8, vitesse: Double = 1.4) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: precision, verticalAccuracy: 5, course: 0, speed: vitesse,
                   timestamp: Date(timeIntervalSince1970: 1_793_260_000))
    }

    @Test func pasSelonLaVitesse() {
        let depart = position(48.8086, 2.4178)
        #expect(TraceRecorder.garder(depart, apres: nil)?.count == 5)
        // ~33 m plus loin à pied : trop près.
        #expect(TraceRecorder.garder(position(48.8089, 2.4178), apres: depart) == nil)
        // ~67 m : gardé à pied, pas en voiture (pas de 100 m).
        #expect(TraceRecorder.garder(position(48.8092, 2.4178), apres: depart) != nil)
        #expect(TraceRecorder.garder(position(48.8092, 2.4178, vitesse: 12), apres: depart) == nil)
        // Imprécis : jamais.
        #expect(TraceRecorder.garder(position(48.82, 2.42, precision: 80), apres: depart) == nil)
    }
}

/// File du tracé précis dans un fichier (03/11) et faux départs ignorés.
struct FileTraceTests {
    func file(maximum: Int = 100) -> FileTrace {
        FileTrace(url: URL.temporaryDirectory.appendingPathComponent("trace-\(UUID().uuidString).csv"), maximum: maximum)
    }

    @Test func ajoutPuisRetraitDesPremiers() throws {
        let f = file()
        #expect(f.compte == 0 && f.lire().isEmpty)
        try f.ajouter([[1_800_000_000, 48.856613, 2.352222, 5, 1.4], [1_800_000_060, 48.857, 2.353, 8, -1]])
        try f.ajouter([[1_800_000_120, 48.858, 2.354, 10, 12.5]])
        #expect(f.compte == 3)
        #expect(f.lire()[0] == [1_800_000_000, 48.856613, 2.352222, 5, 1.4] && f.lire()[1][4] == -1)
        try f.retirerPremiers(2)
        #expect(f.compte == 1 && f.lire() == [[1_800_000_120, 48.858, 2.354, 10, 12.5]])
        // Relu depuis le disque par une autre instance (relance de l'app).
        #expect(FileTrace(url: f.url, maximum: 100).compte == 1)
    }

    @Test func tailleeAuMaximum() throws {
        let f = file(maximum: 10)
        try f.ajouter((0..<12).map { [Double($0), 48, 2, 5, 0] })
        #expect(f.compte == 10 && f.lire().first?[0] == 2)
    }

    @Test func fauxDepartIgnore() {
        let repos = CLLocation(latitude: 48.8566, longitude: 2.3522)
        func point(_ dLat: Double, vitesse: Double = -1, precision: Double = 100) -> CLLocation {
            CLLocation(coordinate: .init(latitude: 48.8566 + dLat, longitude: 2.3522), altitude: 0,
                       horizontalAccuracy: precision, verticalAccuracy: -1, course: -1, speed: vitesse, timestamp: .now)
        }
        #expect(!TraceRecorder.estDepart(point(0.002), repos: repos))          // ~220 m : antenne
        #expect(TraceRecorder.estDepart(point(0.006), repos: repos))           // ~670 m
        #expect(!TraceRecorder.estDepart(point(0.006, precision: 1000), repos: repos))  // position trop floue
        #expect(TraceRecorder.estDepart(point(0.001, vitesse: 3), repos: repos))
        #expect(TraceRecorder.estDepart(point(0), repos: nil))
    }
}
