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

    static func firstMatch(in text: String) -> Match? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let date = match.date, let range = Range(match.range, in: text) else { return nil }
        let hasTime = text[range].range(of: #"\d{1,2}\s*(h|:)"#, options: .regularExpression) != nil
        return Match(range: range, date: date, hasTime: hasTime)
    }

    /// Le texte sans la partie date, nettoyé.
    static func title(of text: String, removing match: Match?) -> String {
        var title = text
        if let match { title.removeSubrange(match.range) }
        return title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
