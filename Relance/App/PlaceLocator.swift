import CoreLocation
import Foundation
import MapKit

/// Coordonnées des adresses des tâches (ligne 📍), demandées à Plans une seule fois puis gardées sur l'appareil.
@MainActor @Observable
final class PlaceLocator {
    static let shared = PlaceLocator()
    private static let key = "placeCoordinates"

    private(set) var coordinates: [String: CLLocationCoordinate2D]
    /// Adresses introuvables pendant cette session : on ne redemande pas à chaque affichage.
    private var failed: Set<String> = []

    private init() {
        let saved = AppGroup.defaults.dictionary(forKey: Self.key) as? [String: [Double]] ?? [:]
        coordinates = saved.compactMapValues { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }

    /// Cherche les adresses encore inconnues (Plans limite le nombre de recherches : une à la fois).
    func locate(_ addresses: [String]) async {
        for address in Set(addresses) where coordinates[address] == nil && !failed.contains(address) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = address
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
                failed.insert(address)
                continue
            }
            let coordinate: CLLocationCoordinate2D
            if #available(iOS 26, macOS 26, *) {
                coordinate = item.location.coordinate
            } else {
                coordinate = item.placemark.coordinate
            }
            coordinates[address] = coordinate
            save()
        }
    }

    private func save() {
        AppGroup.defaults.set(coordinates.mapValues { [$0.latitude, $0.longitude] }, forKey: Self.key)
    }
}
