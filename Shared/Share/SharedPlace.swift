import Foundation

/// Lieu partagé depuis Plans ou Google Maps (plan P9-A3) : nom, adresse et coordonnées lus dans le lien.
/// Les liens courts (`maps.apple/p/…`, `maps.app.goo.gl/…`) sont suivis jusqu'à l'adresse longue, sans charger
/// la page (celle de Google a déjà renvoyé « Dynamic Link Not Found » sur l'iPhone, le 16/10).
///
/// Formats vus le 16/10/2026 sur de vrais partages :
/// - Plans : `https://maps.apple/p/XDMgUNM27LJigH` → `https://maps.apple.com/place?address=5%20Rue…&coordinate=48.812438,2.413660&name=Aromes&place-id=…`
/// - Google Maps : `https://maps.app.goo.gl/5EAQCmL5DBgV24hWA?g_st=…` → `https://maps.google.com/?q=Express+de+Lyon,+1+Rue+de+Lyon,+75012+Paris&ftid=…`
/// Les autres formes (`/maps/place/<nom>/@lat,lon`, `!3d…!4d…`, `ll=`) sont lues aussi, mais pas encore vues en vrai.
nonisolated struct SharedPlace: Equatable, Sendable {
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?

    init(name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
         source: String, category: String? = nil) {
        (self.name, self.address, self.latitude, self.longitude, self.source, self.category)
            = (name, address, latitude, longitude, source, category)
    }
    /// `plans` ou `google` (champ `lieu.source`).
    var source: String
    /// Catégorie de Plans (`MKPOICategoryNightlife`…), demandée à Plans au moment du partage.
    var category: String?

    /// Envie proposée d'après la catégorie de Plans, et la sorte de lieu notée sur la ligne du type
    /// (« 🍽 À tester · bar »). Catégories relevées le 16/10 : Aromes → épicerie, Express de Lyon → bar,
    /// Le P'tit Zinc → restaurant.
    static func envie(forCategory category: String?) -> (kind: ToSee.Kind, label: String?)? {
        guard let category else { return nil }
        let table: [String: (ToSee.Kind, String?)] = [
            "Restaurant": (.restaurant, "restaurant"), "Cafe": (.restaurant, "café"), "Bakery": (.restaurant, "boulangerie"),
            "Nightlife": (.restaurant, "bar"), "Brewery": (.restaurant, "brasserie"), "Winery": (.restaurant, "domaine viticole"),
            "Distillery": (.restaurant, "distillerie"),
            "Store": (.shop, nil), "FoodMarket": (.shop, "épicerie"),
            "Museum": (.outing, "musée"), "Park": (.outing, "parc"), "NationalPark": (.outing, "parc naturel"),
            "Theater": (.outing, "théâtre"), "MovieTheater": (.outing, "cinéma"), "MusicVenue": (.outing, "salle de concert"),
            "Aquarium": (.outing, "aquarium"), "Zoo": (.outing, "zoo"), "AmusementPark": (.outing, "parc d'attractions"),
            "Landmark": (.outing, "monument"), "NationalMonument": (.outing, "monument"), "Castle": (.outing, "château"),
            "Fortress": (.outing, "fort"), "Planetarium": (.outing, "planétarium"), "Library": (.outing, "bibliothèque"),
            "Beach": (.outing, "plage"), "Stadium": (.outing, "stade"),
        ]
        return table[category.replacingOccurrences(of: "MKPOICategory", with: "")].map { (kind: $0.0, label: $0.1) }
    }

    /// Lien de carte, court ou long.
    static func isMapLink(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        return host == "maps.apple" || host == "maps.apple.com" || host == "maps.app.goo.gl"
            || host.hasPrefix("maps.google.") || (host == "goo.gl" && path.hasPrefix("/maps"))
            || ((host.hasPrefix("google.") || host.hasPrefix("www.google.")) && path.hasPrefix("/maps"))
    }

    private static func isShortLink(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "maps.apple" || host == "maps.app.goo.gl" || host == "goo.gl"
    }

    /// Le lieu d'un lien de carte : lu directement, ou après avoir suivi le lien court (4 s au plus).
    static func resolve(_ url: URL) async -> SharedPlace? {
        var current = url
        for _ in 0..<3 {
            if let place = place(in: current) { return place }
            guard isShortLink(current) || isMapLink(current), let next = await redirect(of: current) else { return nil }
            current = next
        }
        return place(in: current)
    }

    /// Nom, adresse et coordonnées d'une adresse longue de Plans ou de Google Maps.
    static func place(in url: URL) -> SharedPlace? {
        guard let host = url.host()?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // Google écrit les espaces « + » dans ses adresses (`q=Express+de+Lyon`), Plans « %20 ».
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.replacingOccurrences(of: "+", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if host == "maps.apple.com" {
            let point = (value("coordinate") ?? value("ll")).flatMap(coordinates)
            let address = value("address").map(withoutCountry)
            guard let name = value("name") ?? value("q") ?? address else { return nil }
            return SharedPlace(name: name, address: address, latitude: point?.0, longitude: point?.1, source: "plans")
        }
        guard isMapLink(url), !isShortLink(url) else { return nil }
        var point = (value("ll") ?? value("center")).flatMap(coordinates) ?? Self.point(inPath: url.absoluteString)
        var name: String?, address: String?
        if let q = value("q") ?? value("query") {
            if let p = coordinates(q) {
                point = point ?? p
            } else {
                (name, address) = split(withoutCountry(q))
            }
        }
        // /maps/place/Express+de+Lyon/@48.84,2.37,17z
        if name == nil, let range = url.path().range(of: #"/place/([^/]+)"#, options: .regularExpression) {
            let raw = url.path()[range].dropFirst("/place/".count)
            let text = String(raw).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(raw)
            (name, address) = split(withoutCountry(text))
        }
        guard let name else {
            guard let point else { return nil }
            return SharedPlace(name: "Point sur la carte", latitude: point.0, longitude: point.1, source: "google")
        }
        return SharedPlace(name: name, address: address, latitude: point?.0, longitude: point?.1, source: "google")
    }

    /// La ligne 📍 : le point exact s'il est connu (lien Plans `ll=`), sinon le lien partagé.
    func contact(link: URL) -> TaskContact {
        let mapsLink = latitude.flatMap { lat in longitude.flatMap { TaskContact.mapsLink(name: name, latitude: lat, longitude: $0) } }
        return TaskContact(name: name, address: address, link: mapsLink ?? link)
    }

    /// Le champ `lieu` (HA), avec le lien partagé tel quel.
    func lieu(link: URL) -> TacheHA.Lieu {
        TacheHA.Lieu(nom: name, adresse: address, telephone: nil,
                     lat: latitude.map(TaskContact.rounded), lon: longitude.map(TaskContact.rounded),
                     lien: link.absoluteString, source: source)
    }

    // MARK: - Lecture

    /// « Express de Lyon, 1 Rue de Lyon, 75012 Paris » → nom, adresse ; une adresse seule (« 1 Rue de Lyon,
    /// 75012 Paris ») sert de nom et d'adresse.
    private static func split(_ text: String) -> (String, String?) {
        let parts = text.components(separatedBy: ", ")
        guard parts.count > 1 else { return (text, nil) }
        if parts[0].first?.isNumber == true { return (text, text) }
        return (parts[0], parts.dropFirst().joined(separator: ", "))
    }

    private static func withoutCountry(_ text: String) -> String {
        text.replacingOccurrences(of: #",\s*France$"#, with: "", options: .regularExpression)
    }

    /// « 48.812438,2.413660 » (bornes vérifiées).
    static func coordinates(_ text: String) -> (Double, Double)? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

    /// `!3d48.84!4d2.37` (le lieu lui-même), sinon `@48.84,2.37,17z` (le centre de la carte).
    private static func point(inPath text: String) -> (Double, Double)? {
        for pattern in [#"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#, #"@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let a = Range(m.range(at: 1), in: text), let b = Range(m.range(at: 2), in: text) else { continue }
            if let p = coordinates("\(text[a]),\(text[b])") { return p }
        }
        return nil
    }

    // MARK: - Lien court

    /// Adresse vers laquelle renvoie le lien court, sans la suivre ni charger de page.
    private static func redirect(of url: URL) async -> URL? {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect.shared, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location") else { return nil }
        return URL(string: location, relativeTo: url)?.absoluteURL
    }
}

/// Refuse les redirections : on veut l'adresse du lien court, pas la page.
private nonisolated final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirect()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
