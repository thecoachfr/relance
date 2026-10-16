import DonneesHA
import Foundation

/// Une tâche telle que rangée dans Home Assistant (espace `aiguillage`, clé = `localID` en minuscules).
///
/// Contrairement à Google Tasks, chaque information a son champ : plus de lignes `⏰`, `🏷`, `🔖`, `❗`, `🔁`
/// en tête des notes. Les autres lignes techniques (`📍`, `🔄`, `👀`, `🗓`, `📅`, `💡`, `🎙`…) restent dans
/// `notes`, comme avant. Lu aussi par la vigie, la routine de tri et l'écran du Nest Hub : garder les noms.
/// Version 2 (plans P9, `plans/P9-00-INDEX.md`) : champ `lieu`, dont la ligne `📍` des notes reste une copie.
nonisolated struct TacheHA: Codable, Equatable, Sendable {
    /// Lieu de la tâche (P9-A). Il fait foi ; la ligne `📍` des notes en est la copie lue par la vigie,
    /// la routine de tri, l'écran du Nest Hub et le mode Google Tasks.
    struct Lieu: Codable, Equatable, Sendable {
        var nom: String
        var adresse: String?
        var telephone: String?
        var lat: Double?
        var lon: Double?
        var lien: String?
        /// `plans`, `google`, `photo`, `gps`, `memo` ou `saisie` ; absent si inconnu.
        var source: String?
    }

    /// Envie (P9-A2, B1) : type, note, plateforme… Elle fait foi ; la ligne du type (`🎬 À regarder`…) en est la
    /// copie. Les champs que l'app ne connaît pas (`tmdb`, `dispo_fr`, `dispo_maj`, écrits par la vigie en B3)
    /// sont gardés tels quels.
    struct Envie: Codable, Equatable, Sendable {
        /// `voir`, `resto`, `magasin`, `spot_photo`, `lire`, `ecouter`, `regarder`.
        var type: String
        var note: String?
        /// `netflix`, `apple_tv`, `disney`, `canal`, `prime`, `youtube`, `france_tv`, `arte`, `spotify`…
        var plateforme: String?
        var idTitre: String?
        var lien: String?
        /// Champs écrits par d'autres (vigie, routine), recopiés sans y toucher.
        var autres: [String: JSONValeur] = [:]

        init(type: String, note: String? = nil, plateforme: String? = nil, idTitre: String? = nil, lien: String? = nil) {
            (self.type, self.note, self.plateforme, self.idTitre, self.lien) = (type, note, plateforme, idTitre, lien)
        }

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ s: String) { stringValue = s }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        private static let known = ["type", "note", "plateforme", "id_titre", "lien"]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            type = try c.decode(String.self, forKey: Key("type"))
            note = try c.decodeIfPresent(String.self, forKey: Key("note"))
            plateforme = try c.decodeIfPresent(String.self, forKey: Key("plateforme"))
            idTitre = try c.decodeIfPresent(String.self, forKey: Key("id_titre"))
            lien = try c.decodeIfPresent(String.self, forKey: Key("lien"))
            for key in c.allKeys where !Self.known.contains(key.stringValue) {
                autres[key.stringValue] = try c.decode(JSONValeur.self, forKey: key)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(type, forKey: Key("type"))
            try c.encodeIfPresent(note, forKey: Key("note"))
            try c.encodeIfPresent(plateforme, forKey: Key("plateforme"))
            try c.encodeIfPresent(idTitre, forKey: Key("id_titre"))
            try c.encodeIfPresent(lien, forKey: Key("lien"))
            for (key, value) in autres where !Self.known.contains(key) { try c.encode(value, forKey: Key(key)) }
        }
    }

    /// Version du format : 2 dès qu'un champ P9 est présent.
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
    var lieu: Lieu?
    var envie: Envie?

    enum CodingKeys: String, CodingKey {
        case v, titre, notes, jour, heure, categorie, priorite, tags, relances, fait, lieu, envie
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
        // Un lieu mal formé (écrit à la main, autre version) ne doit pas rendre la tâche illisible.
        lieu = try? c.decodeIfPresent(Lieu.self, forKey: .lieu)
        envie = try? c.decodeIfPresent(Envie.self, forKey: .envie)
    }

    /// Les champs absents ne sont pas écrits (JSON plus lisible pour la routine et la vigie).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lieu == nil && envie == nil ? v : max(v, 2), forKey: .v)
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
        try c.encodeIfPresent(lieu, forKey: .lieu)
        try c.encodeIfPresent(envie, forKey: .envie)
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
