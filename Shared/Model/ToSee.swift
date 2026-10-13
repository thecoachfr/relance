import Foundation

/// « À voir » : à garder sans échéance (expo, film, lieu à découvrir), éventuellement avec une période
/// (« du 10/09/2026 au 31/01/2027 »). Deux lignes des notes, cachées du champ Notes :
/// « 👀 À voir » et « 🗓 Du 10/09/2026 au 31/01/2027 » (ou « 🗓 Jusqu'au … », « 🗓 À partir du … »).
nonisolated struct ToSee: Equatable, Sendable {
    static let marker = "👀 À voir"
    static let periodMarker = "🗓"

    /// Premier et dernier jour (début de journée), facultatifs.
    var start: Date?
    var end: Date?

    init(start: Date? = nil, end: Date? = nil) {
        (self.start, self.end) = (start, end)
    }

    init?(notes: String) {
        let lines = notes.components(separatedBy: "\n").map(Self.clean)
        guard lines.contains(where: { $0.hasPrefix(Self.marker) }) else { return nil }
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

    // MARK: - Lignes des notes

    var lines: [String] {
        var lines = [Self.marker]
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
            return !c.hasPrefix(marker) && !c.hasPrefix(periodMarker)
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
