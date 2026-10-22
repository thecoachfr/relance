import CoreLocation
import UIKit

/// Un arrêt relevé par iOS (`CLVisit`), tel qu'envoyé à Home Assistant (P9-M2). Heures en secondes Unix.
nonisolated struct VisiteTrajet: Codable, Equatable, Sendable {
    var arrivee: Int
    /// Absent tant qu'on n'est pas reparti : iOS renvoie la même visite au départ.
    var depart: Int?
    var lat: Double
    var lon: Double
    var precision: Double

    /// Visite iOS → arrêt, ou nil si l'heure d'arrivée est inconnue (iOS met alors `distantPast`).
    init?(arrivee: Date, depart: Date, lat: Double, lon: Double, precision: Double) {
        guard arrivee != .distantPast, arrivee.timeIntervalSince1970 > 0, precision >= 0 else { return nil }
        self.arrivee = Int(arrivee.timeIntervalSince1970)
        self.depart = depart == .distantFuture ? nil : Int(depart.timeIntervalSince1970)
        self.lat = lat
        self.lon = lon
        self.precision = (precision * 10).rounded() / 10
    }
}

/// File des arrêts pas encore envoyés, gardée dans l'App Group (survit à l'arrêt de l'app).
nonisolated enum TrajetsFile {
    static let maximum = 500

    /// Ajoute un arrêt ; la même arrivée remplace l'ancienne version (le départ connu est gardé).
    static func ajout(_ file: [VisiteTrajet], _ visite: VisiteTrajet) -> [VisiteTrajet] {
        var file = file
        if let i = file.firstIndex(where: { $0.arrivee == visite.arrivee }) {
            var nouvelle = visite
            nouvelle.depart = visite.depart ?? file[i].depart
            file[i] = nouvelle
        } else {
            file.append(visite)
        }
        return Array(file.suffix(maximum))
    }

    /// Après un envoi réussi : retire ce qui est parti, sauf les arrêts mis à jour entre-temps.
    static func apresEnvoi(_ file: [VisiteTrajet], envoyes: [VisiteTrajet]) -> [VisiteTrajet] {
        file.filter { !envoyes.contains($0) }
    }
}

/// Historique des trajets (P9-M2) : iOS relève les arrêts (arrivée, départ, point) à très faible coût, même app
/// fermée (il relance l'app pour chaque visite). Les arrêts attendent dans une file et partent par lots au webhook de
/// l'app (`action: trajets`), au plus toutes les 3 h en arrière-plan, et à chaque retour au premier plan.
/// Les points GPS de l'app Compagnon sont gardés à part par Home Assistant (M1) : rien de plus à suivre ici.
@MainActor
final class TrajetsRecorder: NSObject, CLLocationManagerDelegate {
    static let shared = TrajetsRecorder()
    static let intervalleEnvoi: TimeInterval = 3 * 3600

    private static let actifKey = "trajets.actif"
    private static let fileKey = "trajets.file"
    private static let envoiKey = "trajets.dernierEnvoi"

    private let location = CLLocationManager()
    private var envoiEnCours = false

    /// Interrupteur de Réglages › Mes trajets (coupé par défaut).
    static var isOn: Bool {
        get { AppGroup.defaults.bool(forKey: actifKey) }
        set { AppGroup.defaults.set(newValue, forKey: actifKey) }
    }

    static var file: [VisiteTrajet] {
        get {
            guard let data = AppGroup.defaults.data(forKey: fileKey) else { return [] }
            return (try? JSONDecoder().decode([VisiteTrajet].self, from: data)) ?? []
        }
        set { AppGroup.defaults.set(try? JSONEncoder().encode(newValue), forKey: fileKey) }
    }

    static var dernierEnvoi: Date? { AppGroup.defaults.object(forKey: envoiKey) as? Date }

    var authorization: CLAuthorizationStatus { location.authorizationStatus }

    /// À appeler au lancement : iOS relance l'app pour chaque visite et prévient ce délégué.
    func start() {
        location.delegate = self
        appliquer()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { _ in
            Task { @MainActor in await TrajetsRecorder.shared.envoyer(force: true) }
        }
    }

    func activer(_ on: Bool) {
        Self.isOn = on
        if on {
            if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
            location.requestAlwaysAuthorization()
        }
        appliquer()
    }

    /// Les visites ne sont livrées qu'avec la localisation « Toujours ».
    private func appliquer() {
        if Self.isOn && location.authorizationStatus == .authorizedAlways {
            location.startMonitoringVisits()
        } else {
            location.stopMonitoringVisits()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let c = visit.coordinate
        guard let arret = VisiteTrajet(arrivee: visit.arrivalDate, depart: visit.departureDate, lat: c.latitude,
                                       lon: c.longitude, precision: visit.horizontalAccuracy) else { return }
        EnergyMetrics.count(.visite)
        Task { @MainActor in
            Self.file = TrajetsFile.ajout(Self.file, arret)
            await envoyer(force: false)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in appliquer() }
    }

    /// Envoie la file au webhook. Sans `force`, seulement si le dernier envoi date de plus de 3 h.
    func envoyer(force: Bool) async {
        let file = Self.file
        guard !envoiEnCours, !file.isEmpty, let url = PushRegistration.webhookURL else { return }
        if !force, let dernier = Self.dernierEnvoi, Date.now.timeIntervalSince(dernier) < Self.intervalleEnvoi { return }
        envoiEnCours = true
        defer { envoiEnCours = false }
        // Réveil en arrière-plan : quelques secondes de plus pour finir l'envoi.
        let tache = UIApplication.shared.beginBackgroundTask(withName: "trajets")
        defer { if tache != .invalid { UIApplication.shared.endBackgroundTask(tache) } }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let visites = file.map { v -> [String: Any] in
            var d: [String: Any] = ["arrivee": v.arrivee, "lat": v.lat, "lon": v.lon, "precision": v.precision]
            if let depart = v.depart { d["depart"] = depart }
            return d
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "action": "trajets", "device": UIDevice.current.name, "visites": visites,
        ])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            SyncLog.add("Trajets : envoi de \(file.count) arrêt(s) impossible, nouvel essai plus tard")
            return
        }
        Self.file = TrajetsFile.apresEnvoi(Self.file, envoyes: file)
        AppGroup.defaults.set(Date.now, forKey: Self.envoiKey)
        SyncLog.add("Trajets : \(file.count) arrêt(s) envoyé(s) à Home Assistant")
    }
}
