import Foundation

/// Une envie, gardée sans échéance : une sortie « À voir » (expo, lieu, festival), un resto à tester, un magasin,
/// un spot photo, ou quelque chose « À lire », « À écouter », « À regarder », éventuellement avec une période
/// (« du 10/09/2026 au 31/01/2027 »). Deux lignes des notes, cachées du champ Notes : le type (« 👀 À voir »,
/// « 🍽 À tester », « 🛍 Magasin », « 📷 Spot photo », « 📖 À lire », « 🎧 À écouter », « 🎬 À regarder »), suivi
/// d'une note facultative (« 📷 Spot photo · au couchant »), et « 🗓 Du 10/09/2026 au 31/01/2027 »
/// (ou « 🗓 Jusqu'au … », « 🗓 À partir du … »).
/// Lignes lues aussi par la routine de tri et l'écran du Nest Hub : garder les marqueurs.
nonisolated struct ToSee: Equatable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        // Les envies qui se passent quelque part d'abord (carte), puis les autres.
        case outing, restaurant, shop, photoSpot, read, listen, watch

        var id: Self { self }

        var marker: String {
            switch self {
            case .outing: "👀 À voir"
            case .restaurant: "🍽 À tester"
            case .shop: "🛍 Magasin"
            case .photoSpot: "📷 Spot photo"
            case .read: "📖 À lire"
            case .listen: "🎧 À écouter"
            case .watch: "🎬 À regarder"
            }
        }

        /// « À voir », « Restos à tester »… : titre d'un groupe, d'un choix de type.
        var title: String {
            switch self {
            case .restaurant: "Restos à tester"
            case .shop: "Magasins"
            case .photoSpot: "Spots photo"
            default: String(marker.drop { $0 != " " }.dropFirst())
            }
        }

        /// Libellé court du filtre.
        var shortTitle: String {
            switch self {
            case .outing: "Voir"
            case .restaurant: "Restos"
            case .shop: "Magasins"
            case .photoSpot: "Spots"
            case .read: "Lire"
            case .listen: "Écouter"
            case .watch: "Regarder"
            }
        }

        var symbol: String {
            switch self {
            case .outing: "ticket"
            case .restaurant: "fork.knife"
            case .shop: "bag"
            case .photoSpot: "camera"
            case .read: "book"
            case .listen: "headphones"
            case .watch: "play.tv"
            }
        }

        /// Une envie qui a sa place sur la carte (avec un lieu).
        var isPlace: Bool { [.outing, .restaurant, .shop, .photoSpot].contains(self) }

        /// Le bouton « Fait » : « Vu », « Lu », « Écouté », « Testé », « Photographié ».
        var doneTitle: String {
            switch self {
            case .outing, .watch, .shop: "Vu"
            case .restaurant: "Testé"
            case .photoSpot: "Photographié"
            case .read: "Lu"
            case .listen: "Écouté"
            }
        }

        /// Titre de la section des envies faites.
        var doneSection: String {
            switch self {
            case .outing, .watch, .shop: "Déjà vu"
            case .restaurant: "Déjà testé"
            case .photoSpot: "Déjà photographié"
            case .read: "Déjà lu"
            case .listen: "Déjà écouté"
            }
        }

        /// Exemple dans le champ de la saisie rapide.
        var example: String {
            switch self {
            case .outing: "Expo photo à la MEP"
            case .restaurant: "Le petit italien de la rue de Lyon"
            case .shop: "La boutique de papeterie du Marais"
            case .photoSpot: "Le pont Marie au couchant"
            case .read: "L'Anomalie, Hervé Le Tellier"
            case .listen: "Le dernier album de Feist"
            case .watch: "Perfect Days, Wim Wenders"
            }
        }
    }

    /// Ancienne et première ligne : une sortie.
    static let marker = Kind.outing.marker
    static let markers = Kind.allCases.map(\.marker)
    static let periodMarker = "🗓"

    var kind: Kind
    /// Premier et dernier jour (début de journée), facultatifs.
    var start: Date?
    var end: Date?
    /// Note courte sur la ligne du type (« au couchant, en automne » pour un spot photo).
    var note: String?

    init(_ kind: Kind = .outing, start: Date? = nil, end: Date? = nil, note: String? = nil) {
        (self.kind, self.start, self.end, self.note) = (kind, start, end, note)
    }

    init?(notes: String) {
        let lines = notes.components(separatedBy: "\n").map(Self.clean)
        guard let (kind, line) = Kind.allCases.lazy.compactMap({ k in lines.first { $0.hasPrefix(k.marker) }.map { (k, $0) } }).first
        else { return nil }
        self.kind = kind
        let rest = line.dropFirst(kind.marker.count).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("·") {
            let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            note = text.isEmpty ? nil : text
        }
        guard let period = lines.first(where: { $0.hasPrefix(Self.periodMarker) }) else { return }
        let dates = Self.dates(in: period)
        if period.contains("Jusqu") {
            end = dates.first
        } else if period.contains("partir") {
            start = dates.first
        } else {
            start = dates.first
            end = dates.dropFirst().first
        }
    }

    /// « Dune à regarder », « à lire : L'Anomalie », « l'album de Feist, à écouter » : le type dit dans la phrase,
    /// au début ou à la fin, et la plage à retirer du titre.
    static func kind(in text: String) -> (range: Range<String.Index>, kind: Kind)? {
        let verbs: [(String, Kind)] = [("lire", .read), ("[ée]couter", .listen), ("regarder", .watch), ("voir", .outing),
                                       ("tester", .restaurant)]
        for (verb, kind) in verbs {
            for pattern in [#"[\s,;:–-]*\b(?:à|a)\s+"# + verb + #"\s*[.!]?\s*$"#, #"^\s*(?:à|a)\s+"# + verb + #"\s*[:,–-]\s*"#] {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(m.range, in: text), range.lowerBound > text.startIndex || range.upperBound < text.endIndex
                else { continue }
                return (range, kind)
            }
        }
        return nil
    }

    /// Premier lien des notes (article, vidéo, album, site de l'expo) : le bouton « Ouvrir ».
    static func link(in notes: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: notes, range: NSRange(notes.startIndex..., in: notes))
            .compactMap(\.url).first { $0.scheme == "http" || $0.scheme == "https" }
    }

    // MARK: - Lignes des notes

    var lines: [String] {
        let note = note?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        var lines = [kind.marker + (note.map { $0.isEmpty ? "" : " · " + $0 } ?? "")]
        switch (start, end) {
        case let (s?, e?): lines.append("\(Self.periodMarker) Du \(Self.format(s)) au \(Self.format(e))")
        case let (nil, e?): lines.append("\(Self.periodMarker) Jusqu'au \(Self.format(e))")
        case let (s?, nil): lines.append("\(Self.periodMarker) À partir du \(Self.format(s))")
        case (nil, nil): break
        }
        return lines
    }

    /// Les notes avec ces lignes à la place des anciennes (à la fin), ou sans elles si `toSee` est `nil`.
    static func notes(_ notes: String, setting toSee: ToSee?) -> String {
        var lines = notes.components(separatedBy: "\n").filter {
            let c = clean($0)
            return !markers.contains { c.hasPrefix($0) } && !c.hasPrefix(periodMarker)
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        if let toSee { lines += toSee.lines }
        return lines.joined(separator: "\n")
    }

    // MARK: - Période dans une phrase

    /// « du 10/10/2026 au 31/01/2027 », « du 10 octobre au 31 janvier », « jusqu'au 31/01 », « à partir du 10 octobre »
    /// en fin de phrase. Une fin sans année avant le début passe à l'année suivante.
    static func period(in text: String, now: Date = .now, calendar: Calendar = .current)
        -> (range: Range<String.Index>, toSee: ToSee)? {
        let patterns: [(String, (Date?, Date?) -> ToSee?)] = [
            (#"\bdu\s+(.+?)\s+au\s+(.+?)\s*$"#, { s, e in s != nil && e != nil ? ToSee(start: s, end: e) : nil }),
            (#"\bjusqu['’]\s?au\s+(.+?)\s*$"#, { s, _ in s.map { ToSee(end: $0) } }),
            (#"\b(?:à|a) partir du\s+(.+?)\s*$"#, { s, _ in s.map { ToSee(start: $0) } }),
        ]
        for (pattern, make) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(m.range, in: text) else { continue }
            func part(_ i: Int) -> String? { i < m.numberOfRanges ? Range(m.range(at: i), in: text).map { String(text[$0]) } : nil }
            let first = part(1).flatMap { day(from: $0, now: now, calendar: calendar) }
            var second = part(2).flatMap { day(from: $0, now: now, calendar: calendar) }
            if let s = first, let e = second, e < s { second = calendar.date(byAdding: .year, value: 1, to: e) }
            if let toSee = make(first, second) { return (range, toSee) }
        }
        return nil
    }

    /// « 10/10/2026 », « 31/01 », « 10 octobre 2026 », « 31 janvier » → début de journée.
    private static func day(from text: String, now: Date, calendar: Calendar) -> Date? {
        if let regex = try? NSRegularExpression(pattern: #"^\s*(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\s*$"#),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            func n(_ i: Int) -> Int? { Range(m.range(at: i), in: text).flatMap { Int(text[$0]) } }
            guard let d = n(1), let mo = n(2) else { return nil }
            var y = n(3) ?? calendar.component(.year, from: now)
            if y < 100 { y += 2000 }
            return calendar.date(from: DateComponents(year: y, month: mo, day: d))
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let date = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date else { return nil }
        return calendar.startOfDay(for: date)
    }

    // MARK: - Textes

    /// « Jusqu'au 31 janv. », « Du 10 sept. au 31 janv. », « Plus que 2 semaines », « Dernier jour », « Terminé ».
    func text(now: Date = .now, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        if let end {
            let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
            if days < 0 { return "Terminé le \(Self.short(end))" }
            if days == 0 { return "Dernier jour" }
            if start.map({ $0 <= today }) ?? true {
                if days <= 6 { return "Plus que \(days + 1) jours" }
                if days < 28 { return "Plus que \((days + 1) / 7) semaine\((days + 1) / 7 > 1 ? "s" : "")" }
            }
        }
        if let start, start > today {
            return end.map { "Du \(Self.short(start)) au \(Self.short($0))" } ?? "À partir du \(Self.short(start))"
        }
        return end.map { "Jusqu'au \(Self.short($0))" } ?? "Sans date"
    }

    /// « du 10 oct. au 31 janv. », « jusqu'au 31 janv. », « à partir du 10 oct. ».
    var periodText: String {
        switch (start, end) {
        case let (s?, e?): "du \(Self.short(s)) au \(Self.short(e))"
        case let (nil, e?): "jusqu'au \(Self.short(e))"
        case let (s?, nil): "à partir du \(Self.short(s))"
        case (nil, nil): "sans date"
        }
    }

    func isOver(now: Date = .now, calendar: Calendar = .current) -> Bool {
        end.map { $0 < calendar.startOfDay(for: now) } ?? false
    }

    // MARK: - Dates

    private static func clean(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func dates(in line: String) -> [Date] {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})/(\d{1,2})/(\d{4})"#) else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { m in
            func n(_ i: Int) -> Int? { Range(m.range(at: i), in: line).flatMap { Int(line[$0]) } }
            guard let d = n(1), let mo = n(2), let y = n(3) else { return nil }
            return Calendar.current.date(from: DateComponents(year: y, month: mo, day: d))
        }
    }

    static func format(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", c.day!, c.month!, c.year!)
    }

    private static func short(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
