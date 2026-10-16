import Foundation
import ImageIO

/// Photo partagée depuis Photos (plan P9-A3) : position et date de prise de vue lues dans ses métadonnées.
/// Sans position (photo sans GPS, ou option « Lieu » coupée dans la feuille de partage), on le dit clairement.
nonisolated struct SharedPhoto: Equatable, Sendable {
    var latitude: Double?
    var longitude: Double?
    var date: Date?

    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// Métadonnées d'un fichier ou de données d'image (`CGImageSource`).
    init?(source: CGImageSource) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        self.init(properties: properties)
    }

    init(latitude: Double? = nil, longitude: Double? = nil, date: Date? = nil) {
        (self.latitude, self.longitude, self.date) = (latitude, longitude, date)
    }

    /// `{GPS}` : Latitude / LatitudeRef (N, S), Longitude / LongitudeRef (E, W) ; `{Exif}` : DateTimeOriginal.
    init(properties: [String: Any]) {
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let lat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
           let lon = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue {
            let south = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() == "S"
            let west = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() == "W"
            let point = (south ? -lat : lat, west ? -lon : lon)
            if (-90...90).contains(point.0), (-180...180).contains(point.1), point != (0, 0) {
                (latitude, longitude) = point
            }
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let text = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = formatter.date(from: text)
        }
    }

    /// « Photo du 12 octobre 2026 », gardée dans les notes (pas de vignette : taille des enregistrements).
    var dateLine: String? {
        date.map { "Photo du " + $0.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR"))) }
    }
}

extension SharedPlace {
    /// Coordonnées écrites dans un texte : décimales (« 48.8215, 2.4123 », « 48,8215 ; 2,4123 ») ou en degrés,
    /// minutes, secondes (« 48°49'17.4"N 2°24'44.3"E »). Valeurs hors bornes refusées.
    static func coordinates(inText text: String) -> (Double, Double)? {
        let dms = #"(\d{1,3})\s*°\s*(\d{1,2})\s*['’′]\s*(\d{1,2}(?:[.,]\d+)?)\s*(?:"|''|”|″)?\s*([NSns])[\s,;]+(\d{1,3})\s*°\s*(\d{1,2})\s*['’′]\s*(\d{1,2}(?:[.,]\d+)?)\s*(?:"|''|”|″)?\s*([EOWeow])"#
        if let m = match(dms, in: text) {
            func n(_ i: Int) -> Double? { Double(m[i].replacingOccurrences(of: ",", with: ".")) }
            guard let d1 = n(1), let m1 = n(2), let s1 = n(3), let d2 = n(5), let m2 = n(6), let s2 = n(7) else { return nil }
            let lat = (d1 + m1 / 60 + s1 / 3600) * (m[4].uppercased() == "S" ? -1 : 1)
            let lon = (d2 + m2 / 60 + s2 / 3600) * (m[8].uppercased() == "W" ? -1 : 1)
            return (-90...90).contains(lat) && (-180...180).contains(lon) ? (lat, lon) : nil
        }
        // Décimal : point (« 48.8215, 2.4123 ») ou virgule avec un séparateur clair (« 48,8215 ; 2,4123 », « 48,8215 2,4123 »).
        for pattern in [#"(-?\d{1,3}\.\d+)\s*[,;\s]\s*(-?\d{1,3}\.\d+)"#, #"(-?\d{1,3},\d+)\s*[;\s]\s*(-?\d{1,3},\d+)"#] {
            guard let m = match(pattern, in: text),
                  let lat = Double(m[1].replacingOccurrences(of: ",", with: ".")),
                  let lon = Double(m[2].replacingOccurrences(of: ",", with: ".")) else { continue }
            return (-90...90).contains(lat) && (-180...180).contains(lon) ? (lat, lon) : nil
        }
        return nil
    }

    private static func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}
