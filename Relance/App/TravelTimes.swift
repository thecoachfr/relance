import Foundation
import MapKit

/// Temps de trajet jusqu'à l'adresse d'une tâche, demandé à Plans (pour « Pars maintenant »).
/// Départ : l'adresse réglée (domicile). Les adresses et les durées sont mises en cache pour limiter
/// les appels à Plans (recalcul au plus toutes les 30 min, plus souvent rien ne change).
@MainActor
final class TravelTimes {
    static let shared = TravelTimes()

    private var places: [String: MKMapItem] = [:]
    private var durations: [String: (minutes: Int, at: Date)] = [:]

    func minutes(for item: TaskItem, settings: DepartureSettings) async -> Int? {
        let origin = settings.origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.enabled, !origin.isEmpty,
              let address = TaskContact(notes: item.notes)?.address,
              let due = item.dueInstant(), item.dueMinutes != nil else { return nil }
        // Le trafic change d'un créneau à l'autre : clé au quart d'heure près.
        let slot = Int(due.timeIntervalSince1970 / 900)
        let key = "\(origin)|\(address)|\(settings.mode.rawValue)|\(slot)"
        if let cached = durations[key], Date.now.timeIntervalSince(cached.at) < 1800 { return cached.minutes }

        guard let from = await place(origin), let to = await place(address) else { return nil }
        let request = MKDirections.Request()
        request.source = from
        request.destination = to
        request.transportType = switch settings.mode {
        case .transit: .transit
        case .car: .automobile
        case .walking: .walking
        }
        request.arrivalDate = due
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        let minutes = Int((eta.expectedTravelTime / 60).rounded(.up))
        durations[key] = (minutes, .now)
        return minutes
    }

    /// Itinéraire dans Plans, dans le mode réglé.
    static func mapsURL(to address: String, settings: DepartureSettings) -> URL? {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "daddr", value: address), URLQueryItem(name: "dirflg", value: settings.mode.mapsFlag)]
        return c.url
    }

    private func place(_ address: String) async -> MKMapItem? {
        if let known = places[address] { return known }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        places[address] = item
        return item
    }
}
