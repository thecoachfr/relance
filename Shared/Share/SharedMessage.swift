import Foundation

/// Texte reçu par l'extension de partage (un message WhatsApp, un e-mail, un lien) transformé en tâche.
nonisolated enum SharedMessage {
    /// Première ligne des notes. La variante « titre à revoir » demande au tri de proposer un meilleur titre ;
    /// il la remplace ensuite par `marker`. Si l'utilisateur a retouché le titre, on écrit directement `marker`.
    static let marker = "📩 Message partagé"
    static let titleToReviewMarker = "📩 Message partagé — titre à revoir"

    struct Draft: Equatable {
        var title: String
        /// Début du jour, si une date est dite dans le message.
        var day: Date?
        var minutes: Int?
        var priority: TaskPriority
        /// Le message sans les en-têtes WhatsApp, pour l'aperçu.
        var body: String
    }

    /// En-têtes de WhatsApp quand on partage plusieurs messages :
    /// « [12/10/2026 14:03:15] Paul : … » (iPhone) ou « 12/10/2026 14:03 - Paul: … » (export).
    private static let headers = [
        #"^\[\d{1,2}[/.]\d{1,2}[/.]\d{2,4},? \d{1,2}:\d{2}(:\d{2})?\] [^:\n]{1,40}\s?: "#,
        #"^\d{1,2}[/.]\d{1,2}[/.]\d{2,4},? \d{1,2}:\d{2} - [^:\n]{1,40}\s?: "#,
    ]
    private static let greetings = #"^(salut|bonjour|bonsoir|coucou|hello|hey|hi|cc|yo)\b[\s,!.]*([a-zà-ÿ-]+)?[\s,!.]*$"#
    /// Formules de politesse : jamais un titre de tâche (« J'espère que tout va bien », « Bisous »).
    private static let pleasantries = #"^(j'esp[eè]re que (tout va bien|tu vas bien|vous allez bien|[çc]a va)|comment ([çc]a )?va(s|-tu| tu)?|[çc]a va|tu vas bien|merci( beaucoup| d'avance)?|bisous?|biz|bises|bonne (journée|soirée|fin de journée|semaine)|à (plus|bientôt|demain)|a\+|amitiés|cordialement)\b[\s\p{P}]*\S{0,20}[\s\p{P}]*$"#
    static let maxTitleLength = 60

    static func body(of text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { line in
                headers.reduce(line) { $0.replacingOccurrences(of: $1, with: "", options: .regularExpression) }
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func draft(from text: String, calendar: Calendar = .current) -> Draft {
        let body = body(of: text)
        let priority = TaskPriority.detect(in: body)?.priority ?? .normal
        let match = DateDetection.firstMatch(in: body)

        var title = firstSentence(of: body)
        if let found = DateDetection.firstMatch(in: title) {
            let cleaned = DateDetection.title(of: title, removing: found)
            if !cleaned.isEmpty { title = cleaned }
        }
        title = TaskPriority.removing(TaskPriority.detect(in: title), from: title)
        title = shortened(title)
        title = title.prefix(1).uppercased() + title.dropFirst()

        guard let match else { return Draft(title: title, priority: priority, body: body) }
        let c = calendar.dateComponents([.hour, .minute], from: match.date)
        return Draft(title: title, day: calendar.startOfDay(for: match.date),
                     minutes: match.hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : nil,
                     priority: priority, body: body)
    }

    /// Notes de la tâche : le marqueur, puis le message tel que reçu (en-têtes compris : qui, quand).
    static func notes(original: String, titleEdited: Bool) -> String {
        (titleEdited ? marker : titleToReviewMarker) + "\n" + original.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Première phrase utile : on saute « Salut ! », « Bonjour Paul, »…
    private static func firstSentence(of body: String) -> String {
        if let url = URL(string: body.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host(), url.scheme?.hasPrefix("http") == true {
            return "Lire " + host.replacingOccurrences(of: "www.", with: "")
        }
        let sentences = body
            .replacingOccurrences(of: #"([.!?…])\s+"#, with: "$1\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let useful = sentences.first { sentence in
            // WhatsApp écrit l'apostrophe typographique (’).
            let s = sentence.replacingOccurrences(of: "’", with: "'")
            return s.range(of: greetings, options: [.regularExpression, .caseInsensitive]) == nil
                && s.range(of: pleasantries, options: [.regularExpression, .caseInsensitive]) == nil
        }
        return (useful ?? sentences.first ?? body)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".!?…")))
    }

    /// Coupe à `maxTitleLength` caractères, sur un mot, avec « … ».
    private static func shortened(_ title: String) -> String {
        guard title.count > maxTitleLength else { return title }
        let cut = title.prefix(maxTitleLength)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
    }
}

/// Tâches partagées sans réseau (ou avant la première connexion) : l'app les envoie à sa prochaine synchro.
nonisolated enum PendingShares {
    private static let key = "pendingShares"
    private static var defaults: UserDefaults { Groupes.defaults }

    struct Item: Codable, Equatable {
        var title: String
        var notes: String
        var day: Date?
        var minutes: Int?
        var priority: TaskPriority
    }

    static func add(_ item: Item) {
        var items = load()
        items.append(item)
        defaults.set(try? JSONEncoder().encode(items), forKey: key)
    }

    /// Rend les tâches en attente et vide la file.
    static func takeAll() -> [Item] {
        let items = load()
        if !items.isEmpty { defaults.removeObject(forKey: key) }
        return items
    }

    private static func load() -> [Item] {
        (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }
}
