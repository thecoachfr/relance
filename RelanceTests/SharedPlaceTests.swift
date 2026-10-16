import Foundation
import Testing
@testable import Relance

/// Lieux partagés depuis Plans et Google Maps (P9-A3), sur les liens réels du 16/10/2026.
struct SharedPlaceTests {
    let plansShort = URL(string: "https://maps.apple/p/XDMgUNM27LJigH")!
    let plansLong = URL(string: "https://maps.apple.com/place?address=5%20Rue%20Pierre%20Leroux,%2094140%20Alfortville,%20France&coordinate=48.812438,2.413660&name=Aromes&place-id=IFF6988BA5B55AEB7&map=transit")!
    let googleShort = URL(string: "https://maps.app.goo.gl/5EAQCmL5DBgV24hWA?g_st=fr.alexandrefau.relance.share")!
    let googleLong = URL(string: "https://maps.google.com/?q=Express+de+Lyon,+1+Rue+de+Lyon,+75012+Paris&ftid=0x47e67204ae7ea483:0xf4b2f17966bb0230&entry=gps&shh=CAE")!

    @Test func recognisesMapLinks() {
        for url in [plansShort, plansLong, googleShort, googleLong,
                    URL(string: "https://www.google.com/maps/place/Express+de+Lyon/@48.84,2.37,17z")!] {
            #expect(SharedPlace.isMapLink(url))
        }
        #expect(!SharedPlace.isMapLink(URL(string: "https://www.youtube.com/watch?v=x")!))
        #expect(!SharedPlace.isMapLink(URL(string: "https://www.google.com/search?q=resto")!))
        // Un lien court ne se lit pas sans le suivre.
        #expect(SharedPlace.place(in: googleShort) == nil && SharedPlace.place(in: plansShort) == nil)
    }

    @Test func plansPlace() throws {
        let place = try #require(SharedPlace.place(in: plansLong))
        #expect(place == SharedPlace(name: "Aromes", address: "5 Rue Pierre Leroux, 94140 Alfortville",
                                     latitude: 48.812438, longitude: 2.41366, source: "plans"))
        // Ligne 📍 : le point exact (lien Plans ll=), lisible par la carte.
        let contact = place.contact(link: plansShort)
        #expect(contact.coordinate?.latitude == 48.812438 && contact.address == "5 Rue Pierre Leroux, 94140 Alfortville")
        let lieu = place.lieu(link: plansShort)
        #expect(lieu.lien == plansShort.absoluteString && lieu.source == "plans" && lieu.lat == 48.812438)
    }

    @Test func googlePlace() throws {
        let place = try #require(SharedPlace.place(in: googleLong))
        #expect(place.name == "Express de Lyon" && place.address == "1 Rue de Lyon, 75012 Paris")
        #expect(place.latitude == nil && place.source == "google")
        // Sans coordonnées, la ligne garde le lien partagé ; l'app trouvera l'adresse avec Plans.
        #expect(place.contact(link: googleShort).link == googleShort)

        let path = try #require(SharedPlace.place(in: URL(string:
            "https://www.google.com/maps/place/Express+de+Lyon/@48.8447,2.3739,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d48.8449!4d2.3741")!))
        #expect(path.name == "Express de Lyon" && path.latitude == 48.8449 && path.longitude == 2.3741)

        let address = try #require(SharedPlace.place(in: URL(string: "https://maps.google.com/?q=1+Rue+de+Lyon,+75012+Paris")!))
        #expect(address.name == "1 Rue de Lyon, 75012 Paris" && address.address == address.name)

        let point = try #require(SharedPlace.place(in: URL(string: "https://maps.google.com/?q=48.8519,2.3572")!))
        #expect(point.latitude == 48.8519 && point.name == "Point sur la carte")
    }

    /// Catégories renvoyées par Plans pour les lieux partagés le 16/10.
    @Test func envieFromPlansCategory() {
        #expect(SharedPlace.envie(forCategory: "MKPOICategoryNightlife")! == (.restaurant, "bar"))
        #expect(SharedPlace.envie(forCategory: "MKPOICategoryFoodMarket")! == (.shop, "épicerie"))
        #expect(SharedPlace.envie(forCategory: "MKPOICategoryRestaurant")! == (.restaurant, "restaurant"))
        #expect(SharedPlace.envie(forCategory: "MKPOICategoryStore")! == (.shop, nil))
        #expect(SharedPlace.envie(forCategory: "MKPOICategoryMuseum")?.kind == .outing)
        #expect(SharedPlace.envie(forCategory: "MKPOICategoryPharmacy") == nil)
        #expect(SharedPlace.envie(forCategory: nil) == nil)
        // La sorte de lieu va sur la ligne du type.
        #expect(ToSee(.restaurant, note: "bar").lines == ["🍽 À tester · bar"])
    }

    @Test func errorPagesAreNotTitles() {
        #expect(SharedLink.title(inHTML: "<title>Dynamic Link Not Found</title>") == nil)
        #expect(SharedLink.title(inHTML: "<title>Perfect Days - YouTube</title>") == "Perfect Days")
    }

    /// Suit les vrais liens courts (réseau) : `AIGUILLAGE_TESTS_RESEAU=1` pour le lancer.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIGUILLAGE_TESTS_RESEAU"] == "1"))
    func resolvesRealShortLinks() async throws {
        let plans = try #require(await SharedPlace.resolve(plansShort))
        #expect(plans.name == "Aromes" && plans.latitude != nil)
        let google = try #require(await SharedPlace.resolve(googleShort))
        #expect(google.name == "Express de Lyon")
    }
}
