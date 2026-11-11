import Foundation

/// Lignes techniques des notes, cachées dans le champ Notes parce qu'elles sont déjà montrées ailleurs
/// (📍 dans la section Lieu, 📅 dans la section Agenda) ou ne servent qu'au tri (📩). Elles restent dans
/// Google Tasks : en modifiant le texte visible, on les garde telles quelles.
nonisolated enum NoteLines {
    static let hiddenPrefixes = ["📍", "📅 Dans l'agenda", "📩 Message partagé", "🔔 À l'approche", "🔕 Pas à l'approche", "👀 À voir", "🎟 Sortie", "📌 Rendez-vous", "📖 À lire", "🎧 À écouter", "🎬 À regarder", "🍽 À tester", "⭐ Favori", "🛍 Magasin", "📷 Spot photo", "🗓", "🔄", "↪ Suivante créée", "➕ Proposition", "🛒 Liste :", "📎 ", "🏢 Au bureau", "🏠 À la maison", "📣 Pour info",
                                  // Lien Gmail d'une tâche venue d'un mail (11/11) : montré par « Voir le mail ».
                                  MailOrigine.prefixe]

    static func isHidden(_ line: String) -> Bool {
        let clean = line.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
        return hiddenPrefixes.contains { clean.hasPrefix($0) }
    }

    /// Le texte à montrer et à modifier.
    static func visible(_ notes: String) -> String {
        notes.components(separatedBy: "\n").filter { !isHidden($0) }.joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    /// Les notes complètes après modification du texte visible : les lignes cachées sont gardées
    /// (à la fin). Sans changement visible, les notes restent identiques, à l'octet près.
    static func replacingVisible(in notes: String, with text: String) -> String {
        guard text != visible(notes) else { return notes }
        let hidden = notes.components(separatedBy: "\n").filter(isHidden)
        let body = text.trimmingCharacters(in: .newlines)
        return ([body].filter { !$0.isEmpty } + hidden).joined(separator: "\n")
    }
}

/// Mail d'où vient une tâche (11/11, demande d'Alexandre) : la vigie et l'app Courrier écrivent dans les notes le lien
/// Gmail du fil (`https://mail.google.com/mail/u/0/#inbox/<fil>`) et « 📧 Mail de … ». La fiche montre « Voir le mail »
/// et cache la ligne du lien (gardée dans les données : les autres clients la lisent).
nonisolated enum MailOrigine {
    static let prefixe = "https://mail.google.com/mail/"

    /// Le lien Gmail des notes (première ligne qui en est un), ou nil.
    static func lien(in notes: String) -> URL? {
        for ligne in notes.components(separatedBy: "\n") {
            let propre = ligne.trimmingCharacters(in: .whitespaces)
            if propre.hasPrefix(prefixe), let url = URL(string: propre), url.host == "mail.google.com" { return url }
        }
        return nil
    }

    /// L'identifiant du fil Gmail (dernier élément du fragment, `#inbox/<fil>`), ou nil.
    static func fil(in notes: String) -> String? {
        guard let fragment = lien(in: notes)?.fragment,
              let fil = fragment.split(separator: "/").last.map(String.init),
              !fil.isEmpty, fil.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return fil
    }

    /// Ce que « Voir le mail » ouvre : le lien web Gmail (l'app Gmail le prend si elle est installée). L'app Courrier
    /// ne sait ouvrir qu'un message (`courrier://mail/<id>`), pas un fil : quand elle saura `courrier://fil/<fil>`,
    /// la préférer ici (et ajouter `courrier` à LSApplicationQueriesSchemes).
    static func destination(in notes: String) -> URL? { lien(in: notes) }
}
