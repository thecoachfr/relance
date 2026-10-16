import Foundation
import ImageIO
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

/// Photo et coordonnées partagées (P9-A3, lots 3 et 4).
struct SharedPhotoTests {
    @Test func coordinatesInText() {
        let decimal = SharedPlace.coordinates(inText: "Le spot : 48.8215, 2.4123")
        #expect(decimal?.0 == 48.8215 && decimal?.1 == 2.4123)
        #expect(SharedPlace.coordinates(inText: "48,8215 ; 2,4123")?.1 == 2.4123)
        #expect(SharedPlace.coordinates(inText: "-33.8568 151.2153")?.0 == -33.8568)
        let dms = SharedPlace.coordinates(inText: #"48°49'17.4"N 2°24'44.3"E"#)
        #expect(abs((dms?.0 ?? 0) - 48.821500) < 0.000_01 && abs((dms?.1 ?? 0) - 2.412306) < 0.000_01)
        #expect((SharedPlace.coordinates(inText: "33°51'24.5\"S 151°12'55.2\"E")?.0 ?? 0) < 0)
        // Hors bornes, ou pas des coordonnées (un prix, une heure).
        #expect(SharedPlace.coordinates(inText: "91.5, 2.3") == nil)
        #expect(SharedPlace.coordinates(inText: "Rendez-vous à 14,30 le 12") == nil)
        #expect(SharedPlace.coordinates(inText: "Prix : 12,50 €") == nil)
    }

    @Test func photoMetadata() {
        let photo = SharedPhoto(properties: [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 48.8519, kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: 2.3572, kCGImagePropertyGPSLongitudeRef as String: "W",
            ],
            kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2026:10:12 18:42:05"],
        ])
        #expect(photo.latitude == 48.8519 && photo.longitude == -2.3572 && photo.hasLocation)
        #expect(photo.dateLine == "Photo du 12 octobre 2026")
        // Sans GPS (option « Lieu » coupée) : pas de position, et on le dira.
        let bare = SharedPhoto(properties: [:])
        #expect(!bare.hasLocation && bare.dateLine == nil)
        // Lieu d'une photo : point exact, source « photo », pas de lien.
        let place = SharedPlace(name: "Pont Marie", latitude: 48.8519, longitude: 2.3572, source: "photo")
        #expect(place.lieu(link: nil).lien == nil && place.contact(link: nil).coordinate?.latitude == 48.8519)
    }
}
