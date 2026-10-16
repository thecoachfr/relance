import CoreLocation
import Foundation
import Testing
@testable import Relance

/// Champ `lieu` des tâches dans Home Assistant (plan P9-A1) et sa copie, la ligne 📍 des notes.
struct LieuTests {
    private func decode(_ json: String) throws -> TacheHA {
        try JSONDecoder().decode(TacheHA.self, from: Data(json.utf8))
    }

    private func json(_ tache: TacheHA) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(tache)) as! [String: Any]
    }

    /// Lieu sans adresse (photo) : la ligne 📍 porte le nom et un lien Plans vers le point ;
    /// la tâche se place sur la carte et se réécrit sans rien perdre.
    @Test func placeWithoutAddressRoundTrips() throws {
        let tache = try decode(#"""
        {"v":2,"titre":"Spot du pont","notes":"Au couchant",
         "lieu":{"nom":"Pont de Charenton","lat":48.8215,"lon":2.4123,"source":"photo"}}
        """#)
        let item = TaskItem(title: "")
        tache.apply(to: item)

        let contact = try #require(TaskContact(notes: item.notes))
        #expect(contact.name == "Pont de Charenton" && contact.address == nil)
        #expect(contact.link?.host() == "maps.apple.com")
        #expect(item.notes.hasPrefix("Au couchant\n📍 Pont de Charenton · https://maps.apple.com/?ll=48.8215,2.4123"))
        #expect(item.placeCoordinate?.latitude == 48.8215 && item.placeCoordinate?.longitude == 2.4123)
        #expect(contact.destination == "48.8215,2.4123")

        let written = try json(TacheHA(item))
        let lieu = try #require(written["lieu"] as? [String: Any])
        #expect(written["v"] as? Int == 2)
        #expect(lieu["nom"] as? String == "Pont de Charenton" && lieu["source"] as? String == "photo")
        #expect(lieu["lat"] as? Double == 48.8215 && lieu["lon"] as? Double == 2.4123)
        #expect(lieu["adresse"] == nil)
    }

    /// Ancienne tâche (ligne 📍 seule) : lue comme avant, et le lieu est déduit de la ligne à l'écriture.
    @Test func oldTaskWithLineOnly() throws {
        let tache = try decode(#"{"titre":"Garage","notes":"📍 Garage Martin · 1 rue X, 94220 Charenton · 01 23 45 67 89"}"#)
        #expect(tache.lieu == nil)
        let item = TaskItem(title: "")
        tache.apply(to: item)
        #expect(item.notes == tache.notes && item.placeRaw == nil)

        let lieu = try #require(item.lieu())
        #expect(lieu.nom == "Garage Martin" && lieu.adresse == "1 rue X, 94220 Charenton")
        #expect(lieu.telephone == "01 23 45 67 89" && lieu.lat == nil && lieu.source == nil)
        // La ligne écrite pour la vigie, la routine et le Nest Hub ne change pas.
        #expect(TacheHA(item).notes == tache.notes)
    }

    /// Coordonnées déjà trouvées par Plans pour l'adresse : ajoutées quand la tâche est réécrite.
    @Test func cachedCoordinatesFillTheField() {
        let item = TaskItem(title: "Kiné", notes: "📍 Cabinet · 3 rue Y, 75012 Paris")
        let lieu = item.lieu(cache: ["3 rue Y, 75012 Paris": [48.84123456789, 2.39]])
        #expect(lieu?.lat == 48.841235 && lieu?.lon == 2.39)
        #expect(item.lieu(cache: [:])?.lat == nil)
    }

    /// Lieu reçu de HA puis changé dans l'app : ses anciennes coordonnées et sa source ne suivent pas.
    @Test func changedPlaceDropsOldCoordinates() throws {
        let item = TaskItem(title: "")
        try decode(#"{"titre":"Resto","lieu":{"nom":"Chez Paul","adresse":"5 rue Z, 75011 Paris","lat":48.85,"lon":2.37,"source":"google"}}"#)
            .apply(to: item)
        #expect(item.lieu()?.source == "google" && item.lieu()?.lat == 48.85)

        // Même endroit, téléphone ajouté : coordonnées et source gardées.
        item.notes = TaskContact.notes(item.notes, setting: TaskContact(name: "Chez Paul", address: "5 rue Z, 75011 Paris", phone: "01 11 22 33 44"))
        #expect(item.lieu()?.source == "google" && item.lieu()?.lat == 48.85 && item.lieu()?.telephone == "01 11 22 33 44")

        item.notes = TaskContact.notes(item.notes, setting: TaskContact(name: "Chez Marie", address: "8 rue W, 75011 Paris"))
        #expect(item.lieu()?.source == nil && item.lieu()?.lat == nil && item.placeCoordinate == nil)

        item.notes = TaskContact.notes(item.notes, setting: nil)
        #expect(item.lieu() == nil && TacheHA(item).lieu == nil)
    }

    /// Cas réel du 16/10 : coordonnées partagées, adresse de Plans sans code postal égale au nom. Le point
    /// doit survivre à la réécriture (il était perdu, et avec lui le rappel à l'approche).
    @Test func pointWithAddressWithoutPostcodeSurvives() throws {
        let item = TaskItem(title: "")
        try decode(#"""
        {"titre":"Photographier au 5 Rue de Conflans","notes":"📩 Message partagé\n48.8215, 2.4123\n📷 Spot photo",
         "lieu":{"nom":"5 Rue de Conflans, Charenton-le-Pont","adresse":"5 Rue de Conflans, Charenton-le-Pont","lat":48.8215,"lon":2.4123,"source":"gps"}}
        """#).apply(to: item)
        #expect(item.notes.contains("https://maps.apple.com/?ll=48.8215,2.4123"))
        #expect(item.placeCoordinate?.latitude == 48.8215)
        #expect(TaskContact(notes: item.notes)?.destination == "48.8215,2.4123")

        let lieu = try #require(TacheHA(item).lieu)
        #expect(lieu.lat == 48.8215 && lieu.lon == 2.4123 && lieu.source == "gps")
        #expect(lieu.adresse == "5 Rue de Conflans, Charenton-le-Pont")
    }

    /// Le lieu fait foi : une ligne 📍 différente dans les notes reçues est remplacée.
    @Test func fieldWinsOverLine() throws {
        let item = TaskItem(title: "")
        try decode(#"{"titre":"Pharmacie","notes":"📍 Ancienne · 1 rue A, 75001 Paris","lieu":{"nom":"Pharmacie du parc","adresse":"2 rue B, 75002 Paris"}}"#)
            .apply(to: item)
        #expect(item.notes == "📍 Pharmacie du parc · 2 rue B, 75002 Paris")
    }

    /// Sans lieu : ni champ `lieu` ni version 2 ; un lieu mal formé ne rend pas la tâche illisible.
    @Test func compatibility() throws {
        let plain = try json(TacheHA(titre: "Pain"))
        #expect(plain["v"] as? Int == 1 && plain["lieu"] == nil)

        let broken = try decode(#"{"titre":"Pain","lieu":{"adresse":"sans nom"}}"#)
        #expect(broken.titre == "Pain" && broken.lieu == nil)
    }

    /// Point choisi sur la carte : nom, adresse approximative et lien du point ; l'itinéraire vise le point.
    @Test func pointPickedOnTheMap() {
        let point = CLLocationCoordinate2D(latitude: 48.8519, longitude: 2.3572)
        let contact = PointPickerView.contact(name: " Pont Marie ", address: "Quai de Bourbon, 75004 Paris", at: point)
        #expect(contact.name == "Pont Marie" && contact.address == "Quai de Bourbon, 75004 Paris")
        #expect(contact.destination == "48.8519,2.3572")
        let notes = TaskContact.notes("", setting: contact)
        #expect(TaskContact(notes: notes) == contact)
        #expect(PointPickerView.contact(name: "", address: nil, at: point).name == "Point sur la carte")
    }

    @Test func coordinatesInPlansLinks() {
        let point = TaskContact(name: "Spot", link: TaskContact.mapsLink(name: "Spot", latitude: 48.82151234567, longitude: -2.4))
        #expect(point.coordinate?.latitude == 48.821512 && point.coordinate?.longitude == -2.4)
        #expect(point.mapsURL?.absoluteString == "https://maps.apple.com/?daddr=48.821512,-2.4")

        #expect(TaskContact(name: "X", link: URL(string: "https://maps.apple.com/?ll=91,2")).coordinate == nil)
        #expect(TaskContact(name: "X", link: URL(string: "https://example.com/?ll=48,2")).coordinate == nil)
        #expect(TaskContact(name: "X", link: URL(string: "https://maps.apple.com/?q=Paris")).coordinate == nil)
    }
}
