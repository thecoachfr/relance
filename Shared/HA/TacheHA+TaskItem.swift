import CryptoKit
import DonneesHA
import Foundation

extension TacheHA {
    /// La tâche locale, telle qu'envoyée à HA.
    init(_ item: TaskItem) {
        self.init(titre: item.title)
        lieu = item.lieu(cache: PlaceCoordinates.saved())
        envie = item.envie()
        // La ligne 📍 recopie le lieu (lien Plans du point quand il n'a pas d'adresse).
        notes = lieu.map { TaskContact.notes(item.notes, setting: $0.contact) } ?? item.notes
        liste = item.liste
        notes = Liste.notes(notes, setting: liste)
        duree = item.dueMinutes == nil ? nil : item.dureeMinutes
        pieces = item.pieces
        notes = Piece.notes(notes, setting: pieces)
        jour = Self.jour(item.dueDay)
        heure = item.dueDay == nil ? nil : Self.heure(item.dueMinutes)
        categorie = item.category
        priorite = item.priorityRaw
        tags = item.tags
        relances = item.remindersRaw
        fait = item.isCompleted
        faitLe = item.isCompleted ? Self.timestamp(item.completedAt ?? .now) : nil
        googleID = item.googleID
        actions = item.actions
        autres = item.haExtrasRaw.flatMap { try? JSONDecoder().decode([String: JSONValeur].self, from: Data($0.utf8)) } ?? [:]
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
        // L'envie fait foi aussi : sa ligne de type (avec la note) est réécrite d'après elle ; la période 🗓 reste.
        if let envie, let kind = ToSee.Kind(haType: envie.type) {
            var toSee = ToSee(notes: item.notes) ?? ToSee(kind)
            toSee.kind = kind
            toSee.note = envie.note
            if ToSee(notes: item.notes) != toSee { item.notes = ToSee.notes(item.notes, setting: toSee) }
        }
        item.envieRaw = envie.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        item.dueDay = day
        item.dueMinutes = minutes
        item.category = categorie
        item.priority = priorite.flatMap(TaskPriority.init(rawValue:)) ?? .normal
        item.tags = tags
        item.remindersRaw = relances
        item.isCompleted = fait
        item.completedAt = fait ? (Self.date(faitLe) ?? item.completedAt ?? .now) : nil
        if let googleID { item.googleID = googleID }
        item.actions = actions
        item.liste = liste
        item.listeBaseRaw = item.listeRaw
        item.dureeMinutes = duree
        item.pieces = pieces
        item.haExtrasRaw = autres.isEmpty ? nil : (try? JSONEncoder().encode(autres)).map { String(decoding: $0, as: UTF8.self) }
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

nonisolated extension ToSee.Kind {
    /// Nom du type dans le champ `envie.type` de Home Assistant.
    var haType: String {
        switch self {
        case .outing: "voir"
        case .event: "sortie"
        case .restaurant: "resto"
        case .shop: "magasin"
        case .photoSpot: "spot_photo"
        case .read: "lire"
        case .listen: "ecouter"
        case .watch: "regarder"
        }
    }

    init?(haType: String) {
        guard let kind = Self.allCases.first(where: { $0.haType == haType }) else { return nil }
        self = kind
    }
}

extension TaskItem {
    /// Actions de la tâche (P9-D1), rangées en JSON dans `actionsRaw`.
    var actions: [TacheHA.Action] {
        get { actionsRaw.flatMap { try? JSONDecoder().decode([TacheHA.Action].self, from: Data($0.utf8)) } ?? [] }
        set { actionsRaw = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)).map { String(decoding: $0, as: UTF8.self) } }
    }

    /// Pièces jointes (P9-K), rangées en JSON dans `piecesRaw`.
    var pieces: [TacheHA.Piece] {
        get { piecesRaw.flatMap { try? JSONDecoder().decode([TacheHA.Piece].self, from: Data($0.utf8)) } ?? [] }
        set { piecesRaw = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)).map { String(decoding: $0, as: UTF8.self) } }
    }

    /// Liste d'articles (P9-G), rangée en JSON dans `listeRaw` ; `nil` sans liste.
    var liste: TacheHA.Liste? {
        get { listeRaw.flatMap { try? JSONDecoder().decode(TacheHA.Liste.self, from: Data($0.utf8)) } }
        set { listeRaw = newValue.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) } }
    }

    /// Dernière liste reçue de HA (ancêtre commun de la fusion).
    var listeBase: TacheHA.Liste? {
        listeBaseRaw.flatMap { try? JSONDecoder().decode(TacheHA.Liste.self, from: Data($0.utf8)) }
    }

    /// L'envie à envoyer à HA : type et note des lignes (modifiables dans l'app), complétés par la dernière envie
    /// reçue de HA si le type n'a pas changé (plateforme, identifiant, champs de la vigie). Lien et plateforme
    /// d'après le premier lien des notes pour une envie à regarder, écouter ou lire. `nil` sans envie.
    func envie() -> TacheHA.Envie? {
        guard let toSee = ToSee(notes: notes) else { return nil }
        var envie = TacheHA.Envie(type: toSee.kind.haType, note: toSee.note)
        if let previous = envieRaw.flatMap({ try? JSONDecoder().decode(TacheHA.Envie.self, from: Data($0.utf8)) }),
           previous.type == envie.type {
            (envie.plateforme, envie.idTitre, envie.lien, envie.autres)
                = (previous.plateforme, previous.idTitre, previous.lien, previous.autres)
        }
        if envie.lien == nil, [.watch, .listen, .read, .event].contains(toSee.kind), let url = ToSee.link(in: notes) {
            envie.lien = url.absoluteString
        }
        if let url = envie.lien.flatMap(URL.init(string:)) {
            if envie.plateforme == nil { envie.plateforme = SharedLink.platform(for: url) }
            if envie.idTitre == nil { envie.idTitre = SharedLink.titleID(for: url) }
        }
        return envie
    }
}

/// Disponibilités en France écrites par la vigie dans `envie` (P9-B3, TMDB / JustWatch).
nonisolated struct Availability: Equatable, Sendable {
    struct Provider: Equatable, Sendable {
        var name: String
        var code: String?
    }

    var title: String?
    var year: Int?
    var poster: URL?
    var subscription: [Provider] = []
    var free: [Provider] = []
    var rent: [Provider] = []
    var buy: [Provider] = []
    /// Jour de la vérification (AAAA-MM-JJ).
    var checked: String?
    /// `ambigu` ou `introuvable` quand TMDB n'a pas trouvé une seule œuvre.
    var status: String?

    init?(_ envie: TacheHA.Envie) {
        func text(_ v: JSONValeur?) -> String? { if case .texte(let s)? = v { s } else { nil } }
        func object(_ v: JSONValeur?) -> [String: JSONValeur]? { if case .objet(let o)? = v { o } else { nil } }
        func providers(_ v: JSONValeur?) -> [Provider] {
            guard case .liste(let list)? = v else { return [] }
            // Une plateforme par code (« Netflix » et « Netflix Standard with Ads »).
            var codes = Set<String>()
            return list.compactMap { item in
                guard let o = object(item), let name = text(o["nom"]) else { return nil }
                let code = text(o["code"])
                if let code, !codes.insert(code).inserted { return nil }
                return Provider(name: name, code: code)
            }
        }
        let tmdb = object(envie.autres["tmdb"])
        let dispo = object(envie.autres["dispo_fr"])
        status = text(envie.autres["tmdb_statut"])
        guard tmdb != nil || status != nil else { return nil }
        title = text(tmdb?["titre"])
        if case .entier(let y)? = tmdb?["annee"] { year = y }
        poster = text(tmdb?["affiche"]).flatMap(URL.init(string:))
        subscription = providers(dispo?["abonnement"])
        free = providers(dispo?["gratuit"])
        rent = providers(dispo?["location"])
        buy = providers(dispo?["achat"])
        checked = text(envie.autres["dispo_maj"])
    }
}

extension TaskItem {
    /// Disponibilités connues (envie reçue de HA), `nil` tant que la vigie n'est pas passée.
    var availability: Availability? {
        envieRaw.flatMap { try? JSONDecoder().decode(TacheHA.Envie.self, from: Data($0.utf8)) }.flatMap(Availability.init)
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
