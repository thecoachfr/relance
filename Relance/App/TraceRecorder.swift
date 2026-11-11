import CoreLocation
import os
import DonneesHA
import UIKit

/// Tracé précis en mouvement (P9-M4, 29/10/2026) : un point tous les 50 m à pied, 100 m en voiture, seulement quand
/// on bouge. Depuis le 30/10 (la flèche de localisation restait affichée en permanence avec `CLBackgroundActivitySession`),
/// mécanisme classique : au repos, seuls les « changements de position importants » d'iOS sont surveillés (aucun
/// indicateur, presque rien sur la batterie) et réveillent l'app au départ, comme le départ d'une visite ; le GPS
/// (`startUpdatingLocation`, sans la flèche bleue de l'île dynamique) tourne alors jusqu'à ce qu'iOS le mette en
/// pause à l'arrêt (`pausesLocationUpdatesAutomatically`) : l'app l'arrête. Les 300 à 500 premiers mètres d'un
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
    /// Ancienne file dans les préférences (avant le 03/11) : reprise une fois dans `FileTrace`.
    private static let fileKey = "trace.file"
    private static let reposKey = "trace.repos"
    private static let envoiKey = "trace.dernierEnvoi"
    private static let attenteKey = "trace.attente"
    /// Lot envoyé : 400 points au plus (un enregistrement de `donnees_apps` tient en 64 Ko).
    static let parLot = 400
    static let maximum = 20_000
    static let intervalleEnvoi: TimeInterval = 15 * 60

    private let location = CLLocationManager()
    /// Le GPS tourne (entre un départ et l'arrêt suivant).
    private(set) var enMouvement = false
    private var dernier: CLLocation?
    /// Sécurité (30/10) : la pause automatique d'iOS peut tarder ; sans 50 m parcourus en 2 min, on éteint le GPS
    /// (5 min avant le 03/11, revue batterie : le GPS précis restait allumé 5 min après chaque arrivée).
    private var veille: Task<Void, Never>?
    static let delaiArret: Duration = .seconds(2 * 60)
    /// Un changement de position important à moins de 400 m du dernier arrêt n'est pas un départ (changement
    /// d'antenne, position du réseau qui saute) : le GPS reste éteint (03/11).
    nonisolated static let ecartDepart: CLLocationDistance = 400
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

    /// Points en attente : `[t, lat, lon, précision, vitesse]`, dans un fichier de l'App Group (`FileTrace`).
    /// Avant le 03/11, toute la file (jusqu'à 20 000 points, environ 1 Mo de JSON dans les préférences) était relue
    /// et réécrite à chaque point gardé, sur le fil principal, GPS allumé.
    static let fileTrace: FileTrace = {
        let dossier = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Groupes.app)?
            .appendingPathComponent("Library", isDirectory: true) ?? URL.temporaryDirectory
        let f = FileTrace(url: dossier.appendingPathComponent("trace-en-attente.csv"), maximum: maximum)
        if let data = AppGroup.defaults.data(forKey: fileKey) {
            if let anciens = try? JSONDecoder().decode([[Double]].self, from: data), !anciens.isEmpty {
                Journal.essayer(.stockage, "Reprise de la file du tracé") { try f.ajouter(anciens) }
            }
            AppGroup.defaults.removeObject(forKey: fileKey)
        }
        return f
    }()

    static var file: [[Double]] { fileTrace.lire() }

    /// Dernier arrêt (`[lat, lon]`), pour reconnaître un faux départ.
    static var repos: CLLocation? {
        get {
            guard let c = AppGroup.defaults.array(forKey: reposKey) as? [Double], c.count == 2 else { return nil }
            return CLLocation(latitude: c[0], longitude: c[1])
        }
        set {
            if let c = newValue?.coordinate { AppGroup.defaults.set([c.latitude, c.longitude], forKey: reposKey) }
            else { AppGroup.defaults.removeObject(forKey: reposKey) }
        }
    }

    /// Un changement de position important ressemble-t-il à un départ ? Oui s'il va vite, s'il est loin du dernier
    /// arrêt, ou si l'arrêt n'est pas connu.
    nonisolated static func estDepart(_ p: CLLocation, repos: CLLocation?) -> Bool {
        if p.speed > 1 { return true }
        guard let repos else { return true }
        return p.distance(from: repos) > max(ecartDepart, p.horizontalAccuracy)
    }

    static var dernierEnvoi: Date? { AppGroup.defaults.object(forKey: envoiKey) as? Date }

    /// Après un envoi raté (11/11) : plus de nouvel essai à chaque point avant 2, 4, 8… 30 min (`AttenteApresEchec`).
    static var attente: AttenteApresEchec {
        get {
            AppGroup.defaults.data(forKey: attenteKey)
                .flatMap { try? JSONDecoder().decode(AttenteApresEchec.self, from: $0) } ?? AttenteApresEchec()
        }
        set {
            if newValue == AttenteApresEchec() { AppGroup.defaults.removeObject(forKey: attenteKey) }
            else if let data = try? JSONEncoder().encode(newValue) { AppGroup.defaults.set(data, forKey: attenteKey) }
        }
    }

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
        // Pas de flèche bleue dans l'île dynamique (30/10, remarque d'Alexandre : Pacer n'en montre pas) : avec la
        // localisation « Toujours », iOS ne l'affiche que si l'app la demande ; reste la petite flèche près de l'heure.
        location.showsBackgroundLocationIndicator = false
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { _ in
            // À l'ouverture, un essai même pendant l'attente : le réseau a pu changer (sortie d'un Wi-Fi qui filtre).
            Task { @MainActor in await TraceRecorder.shared.envoyer(force: true, malgreAttente: true) }
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
        surveillerArret()
        SyncLog.add("Tracé précis : départ, GPS allumé")
    }

    /// Relancée à chaque point gardé : 5 min sans point (moins de 50 m parcourus) éteignent le GPS.
    private func surveillerArret() {
        veille?.cancel()
        veille = Task { [weak self] in
            try? await Task.sleep(for: Self.delaiArret)
            guard !Task.isCancelled else { return }
            self?.arreterSuivi()
        }
    }

    private func arreterSuivi() {
        veille?.cancel()
        veille = nil
        guard enMouvement else { return }
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        enMouvement = false
        if let ici = dernier ?? location.location { Self.repos = ici }
        dernier = nil
        SyncLog.add("Tracé précis : arrêt, GPS éteint")
        Task { await envoyer(force: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard Self.actif else { return appliquer() }
            // Réveil par un changement de position important : le GPS prend le relais, sauf faux départ.
            if !enMouvement {
                guard let position = locations.last, Self.estDepart(position, repos: Self.repos) else { return }
                reveiller()
            }
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
        surveillerArret()
        Journal.essayer(.stockage, "Point du tracé") { try Self.fileTrace.ajouter([point]) }
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
    /// Après un échec, rien avant la fin de l'attente (`attente`), sauf `malgreAttente` (ouverture de l'app) ;
    /// les points restent dans la file.
    func envoyer(force: Bool, malgreAttente: Bool = false) async {
        guard !envoiEnCours, Self.fileTrace.compte > 0, let url = HAConfig.url, let jeton = HAConfig.token, !jeton.isEmpty else { return }
        if !malgreAttente, Self.attente.doitAttendre(a: .now) { return }
        if !force, Self.fileTrace.compte < Self.parLot, let d = Self.dernierEnvoi, Date.now.timeIntervalSince(d) < Self.intervalleEnvoi { return }
        envoiEnCours = true
        defer { envoiEnCours = false }
        let file = Self.file
        let tache = UIApplication.shared.beginBackgroundTask(withName: "trace")
        defer { if tache != .invalid { UIApplication.shared.endBackgroundTask(tache) } }
        let client = HAClient(url: url, jeton: jeton, delai: 20)
        var envoyes = 0
        var echec = false
        for debut in stride(from: 0, to: file.count, by: Self.parLot) {
            let lot = Array(file[debut..<min(debut + Self.parLot, file.count)])
            let valeur: JSONValeur = .objet([
                "device": .texte(HAConfig.device),
                "points": .liste(lot.map { .liste($0.map { .nombre($0) }) }),
            ])
            do {
                _ = try await client.lot(espace: TrajetsService.espace, operations: [
                    OperationDonnees(type: .ecrire, cle: "lot:" + UUID().uuidString.lowercased(), valeur: valeur,
                                     versionAttendue: nil, modifieLe: Horodatage.texte(.now), modifiePar: HAConfig.device),
                ])
            } catch is CancellationError {
                break
            } catch {
                // L'erreur d'origine (ErreurHA+Texte : « Home Assistant injoignable : Une erreur SSL… »), sans contenu.
                Journal.echec(.reseau, "Envoi du tracé précis", error)
                echec = true
                break
            }
            envoyes += lot.count
        }
        var attente = Self.attente
        if echec {
            attente.echec(a: .now)
            let minutes = Int((AttenteApresEchec.pause(apres: attente.echecs) / 60).rounded())
            SyncLog.add("Tracé précis : envoi impossible (\(file.count - envoyes) point(s) gardé(s)), nouvel essai dans \(minutes) min")
        } else if envoyes > 0 {
            attente.reussite()
        }
        Self.attente = attente
        guard envoyes > 0 else { return }
        // Les points reçus pendant l'envoi restent dans la file.
        Journal.essayer(.stockage, "File du tracé après l'envoi") { try Self.fileTrace.retirerPremiers(envoyes) }
        AppGroup.defaults.set(Date.now, forKey: Self.envoiKey)
        EnergyMetrics.count(.trace)
        SyncLog.add("Tracé précis : \(envoyes) point(s) envoyé(s) à Home Assistant")
    }
}

/// File des points du tracé en attente d'envoi : une ligne par point (`t,lat,lon,précision,vitesse`), ajoutée en fin
/// de fichier ; réécrite seulement après un envoi, ou pour la tailler à `maximum` points (03/11).
nonisolated final class FileTrace: Sendable {
    let url: URL
    let maximum: Int
    /// Nombre de points dans le fichier, tenu à jour sans le relire (nil : pas encore compté).
    private let nombre = OSAllocatedUnfairLock<Int?>(initialState: nil)

    init(url: URL, maximum: Int) {
        self.url = url
        self.maximum = maximum
    }

    var compte: Int {
        if let n = nombre.withLock({ $0 }) { return n }
        let n = lire().count
        nombre.withLock { $0 = n }
        return n
    }

    func lire() -> [[Double]] {
        guard let texte = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // Une ligne abîmée (écriture interrompue) est ignorée, pas le fichier.
        return texte.split(separator: "\n").compactMap { ligne in
            let v = ligne.split(separator: ",").compactMap { Double($0) }
            return v.count == 5 ? v : nil
        }
    }

    func ajouter(_ points: [[Double]]) throws {
        guard !points.isEmpty else { return }
        let lignes = Data(points.map { $0.map { Self.texte($0) }.joined(separator: ",") + "\n" }.joined().utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lignes)
        } else {
            try lignes.write(to: url, options: .atomic)
        }
        let total = compte + points.count
        nombre.withLock { $0 = total }
        if total > maximum + maximum / 10 { try ecrire(Array(lire().suffix(maximum))) }
    }

    func retirerPremiers(_ n: Int) throws {
        try ecrire(Array(lire().dropFirst(n)))
    }

    private func ecrire(_ points: [[Double]]) throws {
        let texte = points.map { $0.map { Self.texte($0) }.joined(separator: ",") + "\n" }.joined()
        try Data(texte.utf8).write(to: url, options: .atomic)
        nombre.withLock { $0 = points.count }
    }

    /// Sans « .0 » pour les entiers (heure, précision) : la file reste courte.
    static func texte(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }
}
