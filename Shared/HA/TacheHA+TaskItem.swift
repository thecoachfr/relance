import CryptoKit
import Foundation

extension TacheHA {
    /// La tâche locale, telle qu'envoyée à HA.
    init(_ item: TaskItem) {
        self.init(titre: item.title)
        notes = item.notes
        jour = Self.jour(item.dueDay)
        heure = item.dueDay == nil ? nil : Self.heure(item.dueMinutes)
        categorie = item.category
        priorite = item.priorityRaw
        tags = item.tags
        relances = item.remindersRaw
        fait = item.isCompleted
        faitLe = item.isCompleted ? Self.timestamp(item.completedAt ?? .now) : nil
        googleID = item.googleID
    }

    /// Recopie dans la tâche locale ; une échéance déplacée efface le report en cours.
    func apply(to item: TaskItem) {
        let day = day()
        let minutes = day == nil ? nil : minutes
        if day != item.dueDay || minutes != item.dueMinutes { item.snoozedUntil = nil }
        item.title = titre
        item.notes = notes
        item.dueDay = day
        item.dueMinutes = minutes
        item.category = categorie
        item.priority = priorite.flatMap(TaskPriority.init(rawValue:)) ?? .normal
        item.tags = tags
        item.remindersRaw = relances
        item.isCompleted = fait
        item.completedAt = fait ? (Self.date(faitLe) ?? item.completedAt ?? .now) : nil
        if let googleID { item.googleID = googleID }
        item.isDirty = false
    }
}

extension TacheHA {
    /// Espace de noms des clés dérivées d'un identifiant Google (le même que la vigie, `INBOX_NAMESPACE`).
    static let googleNamespace = UUID(uuidString: "6f1c2a3e-1d8b-4e5f-9a7c-2b4d6e8f0a1c")!

    /// Clé HA d'une tâche venue de Google : UUID version 5 de son identifiant, identique sur chaque
    /// appareil et dans la vigie (`uuid.uuid5` en Python), pour qu'une même tâche n'ait qu'une clé.
    static func key(googleID: String) -> UUID {
        var data = withUnsafeBytes(of: googleNamespace.uuid) { Data($0) }
        data.append(Data(googleID.utf8))
        var b = Array(Insecure.SHA1.hash(data: data).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
