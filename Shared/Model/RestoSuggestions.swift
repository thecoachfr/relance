import CoreLocation
import Foundation

/// « Un resto près de… » (P9-S4) : mes restos (favoris d'abord, puis à tester) autour d'un point, triés par distance.
/// Le rayon s'élargit (1 km, 3 km, 10 km) tant qu'il y en a moins de trois. Code pur, testé (`RestoSuggestionsTests`).
nonisolated enum RestoSuggestions {
    struct Place: Equatable, Sendable {
        let id: UUID
        let kind: ToSee.Kind
        let latitude: Double
        let longitude: Double
    }

    struct Hit: Equatable, Sendable {
        let id: UUID
        let kind: ToSee.Kind
        /// En mètres.
        let distance: Double
    }

    static let radii: [Double] = [1_000, 3_000, 10_000]

    /// Le plus petit rayon qui donne au moins `minimum` restos (sinon le plus grand), et ces restos :
    /// favoris d'abord, puis à tester, chacun du plus proche au plus loin.
    static func nearest(_ places: [Place], from origin: CLLocationCoordinate2D, minimum: Int = 3)
        -> (radius: Double, hits: [Hit]) {
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let all = places.filter(\.kind.isRestaurant).map { place in
            Hit(id: place.id, kind: place.kind,
                distance: here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)))
        }
        for radius in radii {
            let hits = all.filter { $0.distance <= radius }
            if hits.count >= minimum || radius == radii.last {
                return (radius, hits.sorted(by: order))
            }
        }
        return (radii.last!, [])
    }

    private static func order(_ a: Hit, _ b: Hit) -> Bool {
        if a.kind != b.kind { return a.kind == .favorite }
        return a.distance < b.distance
    }

    /// « 350 m », « 1,2 km », « 12 km ».
    static func distanceText(_ meters: Double) -> String {
        if meters < 1_000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        if meters < 10_000 { return String(format: "%.1f km", meters / 1_000).replacingOccurrences(of: ".", with: ",") }
        return "\(Int((meters / 1_000).rounded())) km"
    }

    /// Même lieu, à l'écriture près (« Le Pere Fecto » de Plans et « Le Père Fecto » de mes envies).
    static func sameName(_ a: String, _ b: String) -> Bool {
        func clean(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
                .filter { $0.isLetter || $0.isNumber }
        }
        let (x, y) = (clean(a), clean(b))
        guard !x.isEmpty, !y.isEmpty else { return false }
        // « Takesan Donabe Ramen Opéra » et « Takesan Donabe Ramen » ; mais « Chez » ne vaut pas « Chez Miki ».
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        return short == long || (short.count >= 6 && long.hasPrefix(short))
    }
}
