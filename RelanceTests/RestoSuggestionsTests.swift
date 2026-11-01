import CoreLocation
import Foundation
import Testing
@testable import Relance

/// « Un resto près de… » (P9-S4) : rayon qui s'élargit, favoris d'abord, distances, noms proches.
struct RestoSuggestionsTests {
    private let bastille = CLLocationCoordinate2D(latitude: 48.8532, longitude: 2.3691)

    private func place(_ kind: ToSee.Kind, _ lat: Double, _ lon: Double) -> RestoSuggestions.Place {
        .init(id: UUID(), kind: kind, latitude: lat, longitude: lon)
    }

    @Test func favoritesFirstThenNearest() {
        let near = place(.restaurant, 48.8540, 2.3700)      // ≈ 110 m
        let fav = place(.favorite, 48.8560, 2.3720)         // ≈ 380 m
        let mid = place(.restaurant, 48.8580, 2.3740)       // ≈ 650 m
        let shop = place(.shop, 48.8533, 2.3692)
        let found = RestoSuggestions.nearest([mid, shop, near, fav], from: bastille)
        #expect(found.radius == 1_000)
        #expect(found.hits.map(\.id) == [fav.id, near.id, mid.id])
    }

    @Test func radiusGrowsWhenTooFew() {
        let one = place(.restaurant, 48.8540, 2.3700)
        let far = place(.favorite, 48.8700, 2.3500)          // ≈ 2,3 km
        let veryFar = place(.restaurant, 48.9200, 2.3000)    // ≈ 9 km
        #expect(RestoSuggestions.nearest([one, far], from: bastille).radius == 10_000)
        #expect(RestoSuggestions.nearest([one, far, veryFar], from: bastille).hits.count == 3)
        #expect(RestoSuggestions.nearest([], from: bastille).hits.isEmpty)
    }

    @Test func texts() {
        #expect(RestoSuggestions.distanceText(347) == "350 m")
        #expect(RestoSuggestions.distanceText(1_234) == "1,2 km")
        #expect(RestoSuggestions.distanceText(12_400) == "12 km")
        #expect(RestoSuggestions.sameName("Le Pere Fecto", "Le Père Fecto"))
        #expect(RestoSuggestions.sameName("Takesan Donabe Ramen Opéra", "Takesan Donabe Ramen"))
        #expect(!RestoSuggestions.sameName("Chez", "Chez Miki"))
        #expect(LienAiguillage(url: URL(string: "relance://resto")!) == .resto && LienAiguillage.resto.url.absoluteString == "relance://resto")
    }
}
