import DonneesHA
import Foundation

/// Une tâche telle que rangée dans Home Assistant (espace `aiguillage`, clé = `localID` en minuscules).
///
/// Contrairement à Google Tasks, chaque information a son champ : plus de lignes `⏰`, `🏷`, `🔖`, `❗`, `🔁`
/// en tête des notes. Les autres lignes techniques (`📍`, `🔄`, `👀`, `🗓`, `📅`, `💡`, `🎙`…) restent dans
/// `notes`, comme avant. Lu aussi par la vigie, la routine de tri et l'écran du Nest Hub : garder les noms.
nonisolated struct TacheHA: Codable, Equatable, Sendable {
    /// Version du format.
    var v = 1
    var titre: String
    var notes: String = ""
    /// Jour d'échéance, `AAAA-MM-JJ` (jour local, sans fuseau).
    var jour: String?
    /// Heure d'échéance, `HH:MM` ; seulement avec `jour`.
    var heure: String?
    var categorie: String?
    /// `Urgente` ou `Basse` ; absent = Normale.
    var priorite: String?
    var tags: [String] = []
    /// Relances propres à la tâche : l'ancienne ligne des notes, telle quelle (`🔁 Prévenir 1 jour avant · …`).
    var relances: String?
    var fait = false
    /// Horodatage ISO 8601 du « Fait ».
    var faitLe: String?
    /// Identifiant Google Tasks d'origine (tâche migrée ou dictée à Google Home) : évite les doublons.
    var googleID: String?

    enum CodingKeys: String, CodingKey {
        case v, titre, notes, jour, heure, categorie, priorite, tags, relances, fait
        case faitLe = "fait_le"
        case googleID = "google_id"
    }

    init(titre: String) {
        self.titre = titre
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        titre = try c.decodeIfPresent(String.self, forKey: .titre) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        jour = try c.decodeIfPresent(String.self, forKey: .jour)
        heure = try c.decodeIfPresent(String.self, forKey: .heure)
        categorie = try c.decodeIfPresent(String.self, forKey: .categorie)
        priorite = try c.decodeIfPresent(String.self, forKey: .priorite)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        relances = try c.decodeIfPresent(String.self, forKey: .relances)
        fait = try c.decodeIfPresent(Bool.self, forKey: .fait) ?? false
        faitLe = try c.decodeIfPresent(String.self, forKey: .faitLe)
        googleID = try c.decodeIfPresent(String.self, forKey: .googleID)
    }

    /// Les champs absents ne sont pas écrits (JSON plus lisible pour la routine et la vigie).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(titre, forKey: .titre)
        if !notes.isEmpty { try c.encode(notes, forKey: .notes) }
        try c.encodeIfPresent(jour, forKey: .jour)
        try c.encodeIfPresent(heure, forKey: .heure)
        try c.encodeIfPresent(categorie, forKey: .categorie)
        try c.encodeIfPresent(priorite, forKey: .priorite)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encodeIfPresent(relances, forKey: .relances)
        try c.encode(fait, forKey: .fait)
        try c.encodeIfPresent(faitLe, forKey: .faitLe)
        try c.encodeIfPresent(googleID, forKey: .googleID)
    }

    // MARK: - Conversions

    var minutes: Int? {
        guard let heure else { return nil }
        let parts = heure.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func heure(_ minutes: Int?) -> String? {
        minutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
    }

    func day(calendar: Calendar = .current) -> Date? {
        guard let jour else { return nil }
        let parts = jour.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func jour(_ day: Date?, calendar: Calendar = .current) -> String? {
        guard let day else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    func valeur() throws -> JSONValeur { try JSONValeur(self) }

    init(valeur: JSONValeur) throws {
        self = try valeur.decoder(TacheHA.self)
    }
}
