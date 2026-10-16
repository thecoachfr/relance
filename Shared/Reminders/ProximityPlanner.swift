import Foundation

/// Choix des zones de rappel à l'approche (plan P9-A4) : iOS n'en surveille que 20 par app. Avec des dizaines
/// de lieux (restos, spots photo), on garde d'abord quelques places aux tâches urgentes, puis les lieux les plus
/// proches de la position actuelle ; sans position, l'ordre d'avant (priorité, puis échéance).
nonisolated enum ProximityPlanner {
    struct Candidate: Equatable, Sendable {
        var id: String
        var latitude: Double
        var longitude: Double
        var urgent: Bool
        var due: Date?
    }

    static let maxRegions = 20
    /// Places gardées aux tâches urgentes, quelle que soit la distance.
    static let reservedForUrgent = 5

    static func choose(_ candidates: [Candidate], near here: (latitude: Double, longitude: Double)?,
                       max: Int = maxRegions, reserved: Int = reservedForUrgent) -> [String] {
        let byDue: (Candidate, Candidate) -> Bool = { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        let urgent = candidates.filter(\.urgent).sorted(by: byDue).prefix(min(reserved, max))
        let chosen = Set(urgent.map(\.id))
        let others = candidates.filter { !chosen.contains($0.id) }
        let ordered: [Candidate]
        if let here {
            ordered = others.sorted { distance($0, here) < distance($1, here) }
        } else {
            ordered = others.sorted { a, b in a.urgent != b.urgent ? a.urgent : byDue(a, b) }
        }
        return urgent.map(\.id) + ordered.prefix(max - urgent.count).map(\.id)
    }

    /// Distance en mètres (haversine), assez précise à l'échelle d'une ville.
    static func distance(_ c: Candidate, _ here: (latitude: Double, longitude: Double)) -> Double {
        let r = 6_371_000.0, rad = Double.pi / 180
        let dLat = (c.latitude - here.latitude) * rad, dLon = (c.longitude - here.longitude) * rad
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(here.latitude * rad) * cos(c.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}
