import Foundation

/// Fiche du mémo préremplie à partir de ce qu'on partage depuis une autre app :
/// une note (première ligne = sujet), une page web (titre de la page), un lieu de Plans, une fiche contact.
nonisolated enum MemoShareDraft {
    static let maxSubjectLength = 60
    /// Au-delà, une note d'une seule ligne est un contenu, pas un sujet.
    static let maxSingleLineSubject = 40

    /// « 12 rue de la Paix », « 75002 Paris » : une adresse va dans les détails, jamais en sujet.
    static func looksLikeAddress(_ line: String) -> Bool {
        line.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil
            || line.range(of: #"^\d+\s*(bis|ter)?,?\s+(rue|avenue|av\.|boulevard|bd|place|quai|allée|impasse|chemin|route|cours|square|villa|passage)\b"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Contact (Contacts) réduit à ce que le mémo retient.
    struct Contact: Equatable, Sendable {
        var name: String
        var organization: String?
        var jobTitle: String?
        var address: String?
        var phone: String?
        var email: String?
        var url: String?
    }

    /// Lien de collaboration Notes (« Collaborer ») : Notes n'envoie que l'adresse de la note, pas son texte.
    static func isNotesLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.contains(" ") && trimmed.contains("icloud.com/notes/")
    }

    /// Texte partagé, liens et titre de page éventuel → (sujet, détails).
    static func draft(text: String, urls: [String], pageTitle: String?) -> (title: String, details: String) {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let links = urls.filter { url in !lines.contains { $0.contains(url) } }
        var title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // La première ligne sert de sujet seulement si c'en est un : ni une adresse, ni une ligne
        // unique trop longue (le texte entier part alors dans les détails, sujet à taper).
        if title.isEmpty, let first = lines.first, !first.hasPrefix("http"), !looksLikeAddress(first),
           lines.count > 1 || first.count <= maxSingleLineSubject {
            title = first
            lines.removeFirst()
        }
        let hasContent = !lines.isEmpty
        if title.isEmpty, !hasContent, let host = (links.first ?? lines.first).flatMap({ URL(string: $0)?.host() }) {
            title = host.replacingOccurrences(of: "www.", with: "")
        }
        if title.count > maxSubjectLength {
            let cut = title.prefix(maxSubjectLength)
            title = (cut.range(of: " ", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? String(cut)) + "…"
        }
        let details = (lines + links).joined(separator: MemoMerge.separator)
        return (title, details)
    }

    /// Fiche d'un proche choisi dans Contacts : sujet « Prénom Nom (Surnom) »,
    /// détails « surnom X — téléphone — adresse — mention commune » (ex. « ami, catégorie Perso »).
    static func friendCard(givenName: String, familyName: String, nickname: String?, phone: String?,
                           address: String?, birthday: DateComponents? = nil, note: String) -> (title: String, details: String) {
        let name = [givenName, familyName].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let nick = nickname?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = nick.isEmpty ? name : (name.isEmpty ? nick : "\(name) (\(nick))")
        // « anniversaire le 19/11 » : jour et mois seulement (l'année est souvent absente des fiches).
        let birth = birthday.flatMap { b -> String? in
            guard let day = b.day, let month = b.month else { return nil }
            return String(format: "anniversaire le %02d/%02d", day, month)
        }
        let parts = [nick.isEmpty ? nil : "surnom \(nick)", phone, address, birth, note]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (title, parts.joined(separator: MemoMerge.separator))
    }

    /// Fiche contact → (nom, « fonction, société — adresse — téléphone — e-mail — site »).
    static func draft(contact: Contact) -> (title: String, details: String) {
        let role = [contact.jobTitle, contact.organization].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let parts = [role, contact.address, contact.phone, contact.email, contact.url]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let title = contact.name.isEmpty ? (contact.organization ?? "") : contact.name
        return (title, parts.joined(separator: MemoMerge.separator))
    }
}
