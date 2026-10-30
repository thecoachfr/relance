import CoreLocation
import DonneesHA
import UIKit

/// Tracé précis en mouvement (P9-M4, 29/10/2026) : un point tous les 50 m à pied, 100 m en voiture, seulement quand
/// on bouge. Depuis le 30/10 (la flèche de localisation restait affichée en permanence avec `CLBackgroundActivitySession`),
/// mécanisme classique : au repos, seuls les « changements de position importants » d'iOS sont surveillés (aucun
/// indicateur, presque rien sur la batterie) et réveillent l'app au départ, comme le départ d'une visite ; le GPS
/// (`startUpdatingLocation`, flèche visible) tourne alors jusqu'à ce qu'iOS le mette en pause à l'arrêt
/// (`pausesLocationUpdatesAutomatically`) : l'app l'arrête et la flèche disparaît. Les 300 à 500 premiers mètres d'un
/// trajet ne sont pas tracés finement (le temps qu'iOS signale le départ). Coupé par défaut ; « pendant 24 h » ou
/// « toujours ». Les points attendent dans l'App Group et partent par lots dans l'espace `trajets` de `donnees_apps`
/// (`lot:<id>`), rangés par `aiguillage_trajets` (source « precis »). Batterie : mesurée par MetricKit (temps de GPS).
@MainActor
final class TraceRecorder: NSObject, CLLocationManagerDelegate {
    static let shared = TraceRecorder()

    enum Mode: String, CaseIterable, Identifiable {
        case coupe, jour, toujours
        var id: Self { self }
        var titre: String {
            switch self {
            case .coupe: "Coupé"
            case .jour: "Pendant 24 h"
            case .toujours: "Toujours"
            }
        }
    }

    private static let modeKey = "trace.mode"
    private static let finKey = "trace.fin"
    private static let fileKey = "trace.file"
    private static let envoiKey = "trace.dernierEnvoi"
    /// Lot envoyé : 400 points au plus (un enregistrement de `donnees_apps` tient en 64 Ko).
    static let parLot = 400
    static let maximum = 20_000
    static let intervalleEnvoi: TimeInterval = 15 * 60

    private let location = CLLocationManager()
    /// Le GPS tourne (entre un départ et l'arrêt suivant).
    private(set) var enMouvement = false
    private var dernier: CLLocation?
    private var envoiEnCours = false

    static var mode: Mode {
        get { Mode(rawValue: AppGroup.defaults.string(forKey: modeKey) ?? "") ?? .coupe }
        set { AppGroup.defaults.set(newValue.rawValue, forKey: modeKey) }
    }

    /// Fin du mode « pendant 24 h ».
    static var fin: Date? {
        get { AppGroup.defaults.object(forKey: finKey) as? Date }
        set { AppGroup.defaults.set(newValue, forKey: finKey) }
    }

    /// Points en attente : `[t, lat, lon, précision, vitesse]`.
    static var file: [[Double]] {
        get {
            guard let data = AppGroup.defaults.data(forKey: fileKey) else { return [] }
            return (try? JSONDecoder().decode([[Double]].self, from: data)) ?? []
        }
        set { AppGroup.defaults.set(try? JSONEncoder().encode(Array(newValue.suffix(maximum))), forKey: fileKey) }
    }

    static var dernierEnvoi: Date? { AppGroup.defaults.object(forKey: envoiKey) as? Date }

    /// Le tracé tourne en ce moment (mode actif et pas expiré).
    static var actif: Bool {
        switch mode {
        case .coupe: false
        case .toujours: true
        case .jour: (fin ?? .distantPast) > .now
        }
    }

    /// Au lancement (y compris quand iOS relance l'app pour de nouvelles positions) et à chaque changement de mode.
    func start() {
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        location.distanceFilter = 25
        location.pausesLocationUpdatesAutomatically = true
        location.showsBackgroundLocationIndicator = true
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { _ in
            Task { @MainActor in await TraceRecorder.shared.envoyer(force: true) }
        }
        appliquer()
    }

    func choisir(_ mode: Mode) {
        Self.mode = mode
        Self.fin = mode == .jour ? Date.now.addingTimeInterval(24 * 3600) : nil
        if mode != .coupe, location.authorizationStatus != .authorizedAlways { location.requestAlwaysAuthorization() }
        appliquer()
        reveiller()
    }

    private func appliquer() {
        if Self.mode == .jour, !Self.actif { Self.mode = .coupe }
        if Self.actif, location.authorizationStatus == .authorizedAlways {
            location.startMonitoringSignificantLocationChanges()
        } else {
            location.stopMonitoringSignificantLocationChanges()
            arreterSuivi()
        }
    }

    /// Départ détecté (changement de position important, départ d'une visite, ouverture de l'app) : GPS allumé.
    func reveiller() {
        guard Self.actif, location.authorizationStatus == .authorizedAlways, !enMouvement else { return }
        location.allowsBackgroundLocationUpdates = true
        location.startUpdatingLocation()
        enMouvement = true
        SyncLog.add("Tracé précis : départ, GPS allumé")
    }

    private func arreterSuivi() {
        guard enMouvement else { return }
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        enMouvement = false
        dernier = nil
        SyncLog.add("Tracé précis : arrêt, GPS éteint")
        Task { await envoyer(force: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard Self.actif else { return appliquer() }
            // Réveil par un changement de position important : le GPS prend le relais.
            if !enMouvement { reveiller() }
            for position in locations { await recevoir(position) }
        }
    }

    /// iOS a vu qu'on ne bouge plus : on éteint complètement (la flèche disparaît) jusqu'au prochain départ.
    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in arreterSuivi() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in appliquer() }
    }

    /// Garde le point s'il est assez précis et assez loin du précédent (50 m à pied, 100 m au-delà de 30 km/h).
    private func recevoir(_ position: CLLocation) async {
        guard let point = Self.garder(position, apres: dernier) else { return }
        dernier = position
        Self.file = Self.file + [point]
        await envoyer(force: false)
    }

    nonisolated static func garder(_ p: CLLocation, apres dernier: CLLocation?) -> [Double]? {
        guard p.horizontalAccuracy >= 0, p.horizontalAccuracy <= 50 else { return nil }
        if let dernier {
            let pas: CLLocationDistance = p.speed > 8.3 ? 100 : 50
            guard p.distance(from: dernier) >= pas else { return nil }
        }
        return [p.timestamp.timeIntervalSince1970.rounded(), (p.coordinate.latitude * 1e6).rounded() / 1e6,
                (p.coordinate.longitude * 1e6).rounded() / 1e6, p.horizontalAccuracy.rounded(),
                p.speed >= 0 ? (p.speed * 10).rounded() / 10 : -1]
    }

    /// Lots de 400 points vers Home Assistant ; sans `force`, au plus tous les quarts d'heure (ou dès 400 points).
    func envoyer(force: Bool) async {
        let file = Self.file
        guard !envoiEnCours, !file.isEmpty, let url = HAConfig.url, let jeton = HAConfig.token, !jeton.isEmpty else { return }
        if !force, file.count < Self.parLot, let d = Self.dernierEnvoi, Date.now.timeIntervalSince(d) < Self.intervalleEnvoi { return }
        envoiEnCours = true
        defer { envoiEnCours = false }
        let tache = UIApplication.shared.beginBackgroundTask(withName: "trace")
        defer { if tache != .invalid { UIApplication.shared.endBackgroundTask(tache) } }
        let client = HAClient(url: url, jeton: jeton, delai: 20)
        var envoyes = 0
        for debut in stride(from: 0, to: file.count, by: Self.parLot) {
            let lot = Array(file[debut..<min(debut + Self.parLot, file.count)])
            let valeur: JSONValeur = .objet([
                "device": .texte(HAConfig.device),
                "points": .liste(lot.map { .liste($0.map { .nombre($0) }) }),
            ])
            let ok = await Journal.essayer(.reseau, "Envoi du tracé précis", {
                try await client.lot(espace: TrajetsService.espace, operations: [
                    OperationDonnees(type: .ecrire, cle: "lot:" + UUID().uuidString.lowercased(), valeur: valeur,
                                     versionAttendue: nil, modifieLe: Horodatage.texte(.now), modifiePar: HAConfig.device),
                ])
            }) != nil
            guard ok else { break }
            envoyes += lot.count
        }
        guard envoyes > 0 else {
            SyncLog.add("Tracé précis : envoi de \(file.count) point(s) impossible, nouvel essai plus tard")
            return
        }
        // Les points reçus pendant l'envoi restent dans la file.
        Self.file = Array(Self.file.dropFirst(envoyes))
        AppGroup.defaults.set(Date.now, forKey: Self.envoiKey)
        EnergyMetrics.count(.trace)
        SyncLog.add("Tracé précis : \(envoyes) point(s) envoyé(s) à Home Assistant")
    }
}
