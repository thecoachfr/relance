import MapKit

/// Demande à Plans la catégorie d'un lieu partagé (bar, restaurant, épicerie, musée…), et ses coordonnées
/// quand le lien n'en donnait pas (Google Maps). Recherche par le nom autour du point, sinon avec l'adresse.
enum PlaceCategory {
    static func complete(_ place: SharedPlace) async -> SharedPlace {
        let request = MKLocalSearch.Request()
        request.resultTypes = .pointOfInterest
        let center = place.latitude.flatMap { lat in place.longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
        if let center {
            request.naturalLanguageQuery = place.name
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 400, longitudinalMeters: 400)
        } else {
            request.naturalLanguageQuery = [place.name, place.address].compactMap { $0 }.joined(separator: ", ")
        }
        guard let items = try? await MKLocalSearch(request: request).start().mapItems,
              let match = items.first(where: { matches($0, place, center: center) }) else { return place }
        var completed = place
        completed.category = match.pointOfInterestCategory?.rawValue
        if center == nil {
            let coordinate: CLLocationCoordinate2D
            if #available(iOS 26, *) { coordinate = match.location.coordinate } else { coordinate = match.placemark.coordinate }
            (completed.latitude, completed.longitude) = (coordinate.latitude, coordinate.longitude)
        }
        return completed
    }

    /// Même nom (sans tenir compte des majuscules ni des accents) et, si le point est connu, à moins de 300 m.
    private static func matches(_ item: MKMapItem, _ place: SharedPlace, center: CLLocationCoordinate2D?) -> Bool {
        func folded(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        guard let name = item.name.map(folded) else { return false }
        let wanted = folded(place.name)
        guard name.contains(wanted) || wanted.contains(name) else { return false }
        guard let center else { return true }
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) { coordinate = item.location.coordinate } else { coordinate = item.placemark.coordinate }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < 300
    }

    /// Nom et adresse d'un point (photo, coordonnées), proposés par Plans.
    static func describe(latitude: Double, longitude: Double) async -> (name: String?, address: String?) {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else { return (nil, nil) }
            let address = (item.address?.shortAddress ?? item.address?.fullAddress)?
                .replacingOccurrences(of: "\n", with: ", ")
                .replacingOccurrences(of: #",\s*France$"#, with: "", options: .regularExpression)
            return (item.name, address)
        }
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return (nil, nil) }
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let city = [placemark.postalCode, placemark.locality].compactMap { $0 }.joined(separator: " ")
        let address = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
        return (placemark.areasOfInterest?.first ?? placemark.name, address.isEmpty ? nil : address)
    }
}
