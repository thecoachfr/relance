import Foundation

/// Repère une échéance dans une phrase (« appeler le garage vendredi 15 h »).
/// Utilisé par la saisie rapide de l'iPhone et par la dictée sur la montre.
nonisolated enum DateDetection {
    struct Match {
        var range: Range<String.Index>
        var date: Date
        /// Vrai si la phrase précise une heure (« 15 h », « 9:30 »).
        var hasTime: Bool
    }

    static func firstMatch(in text: String, now: Date = .now) -> Match? {
        if let relative = relativeMatch(in: text, now: now) { return relative }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let date = match.date, let range = Range(match.range, in: text) else { return nil }
        let hasTime = text[range].range(of: #"\d{1,2}\s*(h|:)"#, options: .regularExpression) != nil
        return Match(range: range, date: date, hasTime: hasTime)
    }

    // MARK: - « dans 2 heures », « dans une demi-heure », « dans 20 min » (absent du détecteur d'Apple en français)

    private static let numbers: [String: Int] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8,
        "neuf": 9, "dix": 10, "quinze": 15, "vingt": 20, "trente": 30, "quarante": 40, "quarante-cinq": 45,
    ]

    private static func relativeMatch(in text: String, now: Date) -> Match? {
        let pattern = #"\bdans (une demi-heure|un quart d['’]heure|(\d+|[a-z-]+) ?(heures?|h|minutes?|min)\b( et demie)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range, in: text) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { text[$0].lowercased() } }
        let minutes: Int?
        switch group(1)?.replacingOccurrences(of: "’", with: "'") {
        case "une demi-heure": minutes = 30
        case "un quart d'heure": minutes = 15
        default:
            let count = group(2).flatMap { Int($0) ?? numbers[$0] }
            let isHours = group(3)?.hasPrefix("h") == true
            minutes = count.map { isHours ? $0 * 60 + (group(4) != nil ? 30 : 0) : $0 }
        }
        guard let minutes, minutes > 0, minutes <= 24 * 60 else { return nil }
        return Match(range: range, date: now.addingTimeInterval(TimeInterval(minutes) * 60), hasTime: true)
    }

    /// Le texte sans la partie date, nettoyé.
    static func title(of text: String, removing match: Match?) -> String {
        var title = text
        if let match { title.removeSubrange(match.range) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Le détecteur ne prend que « soir » dans « ce soir » : on retire les petits mots restés en fin de phrase.
        if match != nil {
            title = title.replacingOccurrences(of: #"(\s+(ce|cet|cette|à|a|le|la|pour|avant|d'ici|dès))+$"#,
                                               with: "", options: [.regularExpression, .caseInsensitive])
        }
        return title
    }
}
