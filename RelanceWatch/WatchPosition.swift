import CoreLocation
import SwiftUI

/// « Marquer ma position » (30/10) : la montre lit sa position (son GPS, ou celui de l'iPhone à proximité) et l'envoie
/// à l'iPhone, qui crée une tâche « Position du … » avec l'adresse (À trier ; la routine de tri la range).
@MainActor
final class WatchPositionMarker: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    private var attente: CheckedContinuation<CLLocation?, Never>?

    /// La position actuelle (précise à 100 m au moins), ou `nil` si refusée ou introuvable.
    func lire() async -> CLLocation? {
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        return await withCheckedContinuation { suite in
            attente = suite
            location.requestLocation()
        }
    }

    private func finir(_ position: CLLocation?) {
        attente?.resume(returning: position)
        attente = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let meilleure = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 100 }
            .min { $0.horizontalAccuracy < $1.horizontalAccuracy }
        Task { @MainActor in finir(meilleure) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Autorisation pas encore donnée : la réponse arrive par `locationManagerDidChangeAuthorization`.
        if (error as? CLError)?.code == .locationUnknown { return }
        Task { @MainActor in finir(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let statut = manager.authorizationStatus
        Task { @MainActor in
            switch statut {
            case .authorizedWhenInUse, .authorizedAlways: location.requestLocation()
            case .denied, .restricted: finir(nil)
            default: break
            }
        }
    }
}

/// Feuille ouverte par la complication : lit la position, l'envoie, confirme, puis se ferme.
struct WatchPositionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var etat = Etat.lecture
    @State private var marqueur = WatchPositionMarker()

    enum Etat: Equatable { case lecture, marquee(Double), introuvable }

    var body: some View {
        VStack(spacing: 10) {
            switch etat {
            case .lecture:
                ProgressView()
                Text("Lecture de ta position…").font(.footnote)
            case .marquee(let precision):
                Image(systemName: "mappin.circle.fill").font(.largeTitle).foregroundStyle(.tint)
                Text("Position marquée").font(.headline)
                Text("à \(Int(precision)) m près · l'adresse sera ajoutée sur l'iPhone")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .introuvable:
                Image(systemName: "location.slash").font(.largeTitle).foregroundStyle(.secondary)
                Text("Position introuvable").font(.headline)
                Text("Autorise la position pour Aiguillage dans les réglages de la montre, ou réessaie dehors.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .task {
            guard let p = await marqueur.lire() else { return etat = .introuvable }
            WatchStore.shared.sendPosition(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude,
                                           precision: p.horizontalAccuracy, at: p.timestamp)
            etat = .marquee(p.horizontalAccuracy)
            try? await Task.sleep(for: .seconds(3))
            dismiss()
        }
    }
}
