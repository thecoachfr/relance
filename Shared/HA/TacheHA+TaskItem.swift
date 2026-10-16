import CryptoKit
import Foundation

extension TacheHA {
    /// La tâche locale, telle qu'envoyée à HA.
    init(_ item: TaskItem) {
        self.init(titre: item.title)
        lieu = item.lieu(cache: PlaceCoordinates.saved())
        // La ligne 📍 recopie le lieu (lien Plans du point quand il n'a pas d'adresse).
        notes = lieu.map { TaskContact.notes(item.notes, setting: $0.contact) } ?? item.notes
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
        // Le lieu fait foi : la ligne 📍 est réécrite d'après lui. Sans lieu (ancienne tâche, mode Google),
        // la ligne des notes reste la seule source.
        item.notes = lieu.map { TaskContact.notes(notes, setting: $0.contact) } ?? notes
        item.placeRaw = lieu.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
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

nonisolated extension TacheHA.Lieu {
    /// Lieu tiré de la ligne 📍 (coordonnées comprises si son lien Plans en porte).
    init(_ contact: TaskContact) {
        self.init(nom: contact.name, adresse: contact.address, telephone: contact.phone,
                  lat: contact.coordinate?.latitude, lon: contact.coordinate?.longitude,
                  lien: contact.link?.absoluteString)
    }

    /// La ligne 📍 correspondante ; sans lien, un lien Plans vers le point s'il est connu (même avec une
    /// adresse : celle que donne Plans pour un point n'a pas toujours de code postal, et la ligne doit garder
    /// le point, 16/10).
    var contact: TaskContact {
        var link = lien.flatMap(URL.init(string:))
        if link == nil, let lat, let lon {
            link = TaskContact.mapsLink(name: nom, latitude: lat, longitude: lon)
        }
        return TaskContact(name: nom, address: adresse, phone: telephone, link: link)
    }

    /// Même endroit : même nom, ou même adresse.
    func isSamePlace(as other: Self) -> Bool {
        nom == other.nom || (adresse != nil && adresse == other.adresse)
    }
}

extension TaskItem {
    /// Le lieu à envoyer à HA : la ligne 📍 actuelle (modifiable dans l'app), complétée par le dernier lieu
    /// reçu de HA s'il s'agit du même endroit (coordonnées, source), sinon par `cache` (adresses déjà
    /// trouvées par Plans). `nil` sans ligne 📍.
    func lieu(cache: [String: [Double]] = [:]) -> TacheHA.Lieu? {
        guard let contact = TaskContact(notes: notes) else { return nil }
        var lieu = TacheHA.Lieu(contact)
        let previous = placeRaw.flatMap { try? JSONDecoder().decode(TacheHA.Lieu.self, from: Data($0.utf8)) }
        if let previous, previous.isSamePlace(as: lieu) {
            lieu.source = previous.source
            if lieu.lat == nil { (lieu.lat, lieu.lon) = (previous.lat, previous.lon) }
            // La ligne ne dit pas toujours l'adresse (adresse seule, sans code postal) : on garde celle connue.
            if lieu.adresse == nil, lieu.nom == previous.nom { lieu.adresse = previous.adresse }
        }
        if lieu.lat == nil, let address = lieu.adresse, let c = cache[address], c.count == 2 {
            (lieu.lat, lieu.lon) = (TaskContact.rounded(c[0]), TaskContact.rounded(c[1]))
        }
        return lieu
    }

    /// Coordonnées connues du lieu sans rien demander à Plans (lieu reçu de HA, lien Plans de la ligne 📍).
    var placeCoordinate: (latitude: Double, longitude: Double)? {
        guard let lieu = lieu(), let lat = lieu.lat, let lon = lieu.lon else { return nil }
        return (lat, lon)
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

/// Coordonnées des adresses déjà trouvées par Plans (`PlaceLocator`), gardées dans l'App Group.
nonisolated enum PlaceCoordinates {
    static let key = "placeCoordinates"

    static func saved() -> [String: [Double]] {
        AppGroup.defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }
}
