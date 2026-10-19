import Foundation

/// Rendez-vous lu dans un texte (P9-L4, 19/10) : capture d'un SMS de rappel, e-mail Doctolib, carton du dentiste
/// photographié, convocation. Le texte vient de Vision (photo, capture) ou du partage ; tout se passe sur
/// l'appareil. On en tire un titre, la date et l'heure, l'adresse et le téléphone, pour pré-remplir la tâche ;
/// le tri garde le dernier mot (catégorie, contact du mémo, titre propre).
nonisolated enum SharedAppointment {
    struct Draft: Equatable {
        var title: String
        var day: Date
        var minutes: Int?
        var address: String?
        var phone: String?
        /// Praticien ou lieu nommé dans le texte (« Dr Berrezgaoui », « Cabinet K-one »), pour le lieu de la tâche.
        var placeName: String?
    }

    /// Mots qui disent un rendez-vous (sans eux, une date dans un texte n'en fait pas un).
    private static let indices = #"\b(rdv|rendez[- ]vous|convocation|consultation|doctolib|docteur|dr\.?|cabinet|s[ée]ance|examen|radiologie|laboratoire|kin[ée]|dentiste|m[ée]decin|ost[ée]o|ophtalmo|dermato|gyn[ée]co|p[ée]diatre|v[ée]t[ée]rinaire|coiffeur|garage|contr[ôo]le technique|entretien|r[ée]union|assembl[ée]e g[ée]n[ée]rale|\bAG\b)\b"#

    /// Titres proposés selon le mot trouvé, du plus précis au plus vague.
    private static let titres: [(String, String)] = [
        (#"dentiste"#, "Rendez-vous chez le dentiste"),
        (#"kin[ée]"#, "Séance de kiné"),
        (#"ost[ée]o"#, "Rendez-vous chez l'ostéopathe"),
        (#"ophtalmo"#, "Rendez-vous chez l'ophtalmologue"),
        (#"dermato"#, "Rendez-vous chez le dermatologue"),
        (#"gyn[ée]co"#, "Rendez-vous chez le gynécologue"),
        (#"p[ée]diatre"#, "Rendez-vous chez le pédiatre"),
        (#"v[ée]t[ée]rinaire"#, "Rendez-vous chez le vétérinaire"),
        (#"radiologie"#, "Examen de radiologie"),
        (#"laboratoire|prise de sang"#, "Prise de sang au laboratoire"),
        (#"coiffeur"#, "Coiffeur"),
        (#"contr[ôo]le technique"#, "Contrôle technique"),
        (#"garage"#, "Rendez-vous au garage"),
        (#"assembl[ée]e g[ée]n[ée]rale|\bAG\b"#, "Assemblée générale"),
        (#"convocation"#, "Convocation"),
        (#"r[ée]union"#, "Réunion"),
        (#"m[ée]decin|docteur|\bdr\b"#, "Rendez-vous chez le médecin"),
    ]

    /// Le rendez-vous du texte, ou `nil` si ce n'en est pas un (pas d'indice, ou pas de date à venir).
    static func detect(in text: String, now: Date = .now, calendar: Calendar = .current) -> Draft? {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.range(of: indices, options: [.regularExpression, .caseInsensitive]) != nil,
              let (day, minutes) = when(in: flat, now: now, calendar: calendar) else { return nil }
        let title = titres.first { flat.range(of: $0.0, options: [.regularExpression, .caseInsensitive]) != nil }?.1
            ?? "Rendez-vous"
        return Draft(title: title, day: day, minutes: minutes, address: address(in: text), phone: phone(in: text),
                     placeName: praticien(in: flat))
    }

    // MARK: - Date et heure

    /// La première date à venir (aujourd'hui compris) et son heure : d'abord les formes françaises courantes
    /// (« mardi 4 novembre 2026 à 14h30 », « le 04/11 à 9h », « 04/11/2026 14:30 »), puis le détecteur d'Apple.
    static func when(in text: String, now: Date = .now, calendar: Calendar = .current) -> (Date, Int?)? {
        let today = calendar.startOfDay(for: now)
        for found in frenchDates(in: text, now: now, calendar: calendar) where found.0 >= today {
            // Heure écrite ailleurs que juste après la date (« Heure : 17ʰ20 » sur un carton) : celle de l'étiquette.
            return (found.0, found.1 ?? labeledTime(in: text) ?? looseTime(in: text))
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let date = m.date, calendar.startOfDay(for: date) >= today, let range = Range(m.range, in: text) else { continue }
            let hasTime = text[range].range(of: #"\d{1,2}\s*(h|:)"#, options: .regularExpression) != nil
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return (calendar.startOfDay(for: date), hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : nil)
        }
        return nil
    }

    /// « Heure : 17h20 », « Heure: 17+20 » (H en exposant lu « + »), « Horaire : 9 h », « à 17ʰ20 » : l'heure qui suit
    /// une étiquette, en minutes depuis minuit.
    static func labeledTime(in text: String) -> Int? {
        let pattern = #"\b(?:heure|horaire)\s*:?\s*(\d{1,2})\s*(?:h|H|ʰ|\+|:|\.)\s*(\d{2})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func g(_ k: Int) -> Int? { Range(m.range(at: k), in: text).flatMap { Int(text[$0]) } }
            guard let h = g(1), (0...23).contains(h) else { continue }
            let mn = g(2) ?? 0
            if (0...59).contains(mn) { return h * 60 + mn }
        }
        return nil
    }

    /// Dernier recours : une heure seule dans le texte (« 17+20 », « 17h20 », « 9 h », « 14:30 ») ; « 48 heures » ou
    /// « +20 » n'en sont pas.
    static func looseTime(in text: String) -> Int? {
        let pattern = #"(?<![\d+])\b([01]?\d|2[0-3])\s?(?:(?:h|H|ʰ)(?:\s?([0-5]\d))?(?![\p{L}\d])|[+:]\s?([0-5]\d)\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func g(_ k: Int) -> Int? { Range(m.range(at: k), in: text).flatMap { Int(text[$0]) } }
        guard let h = g(1) else { return nil }
        return h * 60 + (g(2) ?? g(3) ?? 0)
    }

    private static let mois = ["janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6,
                               "juillet": 7, "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11,
                               "décembre": 12, "decembre": 12, "janv": 1, "févr": 2, "fevr": 2, "avr": 4, "juil": 7,
                               "sept": 9, "oct": 10, "nov": 11, "déc": 12, "dec": 12]

    private static func frenchDates(in text: String, now: Date, calendar: Calendar) -> [(Date, Int?)] {
        let heure = #"(?:\s*(?:à|a|,|-)?\s*(\d{1,2})\s*(?:h|ʰ|:)\s*(\d{2})?)?"#
        let patterns = [
            // 04/11/2026, 4/11, 04.11.26
            #"\b(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?"# + heure,
            // 4 novembre 2026, 4 nov.
            #"\b(\d{1,2})(?:er)?\s+([a-zéû]{3,9})\.?(?:\s+(\d{4}))?"# + heure,
        ]
        var out: [(Int, Date, Int?)] = []
        for (i, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                func g(_ k: Int) -> String? { Range(m.range(at: k), in: text).map { String(text[$0]) } }
                guard let d = g(1).flatMap(Int.init) else { continue }
                let month: Int? = i == 0 ? g(2).flatMap(Int.init) : g(2).flatMap { mois[$0.lowercased()] }
                guard let month, (1...12).contains(month), (1...31).contains(d) else { continue }
                var year = g(3).flatMap(Int.init) ?? calendar.component(.year, from: now)
                if year < 100 { year += 2000 }
                guard var date = calendar.date(from: DateComponents(year: year, month: month, day: d)) else { continue }
                // Sans année, une date passée de plus d'un mois est celle de l'an prochain.
                if g(3) == nil, date < calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: now))! {
                    date = calendar.date(byAdding: .year, value: 1, to: date)!
                }
                var minutes: Int?
                if let h = g(4).flatMap(Int.init), (0...23).contains(h) {
                    let mn = g(5).flatMap(Int.init) ?? 0
                    if (0...59).contains(mn) { minutes = h * 60 + mn }
                }
                out.append((m.range.location, date, minutes))
            }
        }
        return out.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
    }

    // MARK: - Adresse, téléphone, praticien

    static func address(in text: String) -> String? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue),
           let m = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(m.range, in: text) {
            return clean(String(text[range]))
        }
        // « 114 rue Édouard Vaillant, 94140 Alfortville » : numéro, voie, code postal et ville.
        let pattern = #"\b\d{1,4}(?:\s?(?:bis|ter))?,?\s+(?:rue|avenue|av\.|boulevard|bd|place|quai|allée|impasse|chemin|route|cours|square)\s[^\n,]{2,60},?\s+\d{5}\s+[A-ZÀ-Ü][\p{L}' -]{1,40}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range, in: text) else { return nil }
        return clean(String(text[range]))
    }

    static func phone(in text: String) -> String? {
        let pattern = #"(?:\+33\s?|0)[1-9](?:[\s.-]?\d{2}){4}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range, in: text) else { return nil }
        let digits = text[range].filter(\.isNumber)
        let national = digits.hasPrefix("33") ? "0" + digits.dropFirst(2) : Substring(digits)
        guard national.count == 10 else { return String(text[range]) }
        return stride(from: 0, to: 10, by: 2).map { i in
            String(national[national.index(national.startIndex, offsetBy: i)...].prefix(2))
        }.joined(separator: " ")
    }

    /// « Dr Rabii Berrezgaoui », « Docteur Martin », « Cabinet K-one » : le nom tel qu'écrit.
    static func praticien(in text: String) -> String? {
        let pattern = #"\b(?:Dr\.?|Docteur|Cabinet|Centre)\s+(?:[A-ZÀ-Ü][\p{L}'-]+(?:\s+|$)){1,3}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range, in: text) else { return nil }
        return clean(String(text[range]))
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-"))
    }
}
