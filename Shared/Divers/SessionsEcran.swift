import Darwin
import Foundation

/// Empreinte mémoire du processus (`phys_footprint`, la valeur que surveille le système avant d'arrêter l'app).
nonisolated enum Empreinte {
    static func megaoctets() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let resultat = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard resultat == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}

/// Temps passé à l'écran par l'app montre (scenePhase `.active`), avec son pic de mémoire. watchOS suspend et arrête
/// souvent l'app en arrière-plan, c'est normal : seule une session restée ouverte, donc un arrêt pendant que l'app était
/// à l'écran (plantage, limite de mémoire), est un « arrêt inattendu ». Code pur : compilé aussi pour l'iPhone (tests).
nonisolated struct SessionEcran: Codable, Equatable, Sendable {
    var debut: Date
    /// Fermeture normale (sortie de `.active`) ; nil tant que la session est ouverte, ou si l'app a été arrêtée.
    var fin: Date?
    /// Dernière mesure : fin approximative d'une session interrompue.
    var derniereMesure: Date
    var debutMo: Double
    var picMo: Double
    /// Restée ouverte : l'app s'est arrêtée à l'écran sans passer par la fermeture.
    var interrompue = false

    init(debut: Date, mo: Double) {
        self.debut = debut
        self.derniereMesure = debut
        self.debutMo = mo
        self.picMo = mo
    }

    var duree: TimeInterval { (fin ?? derniereMesure).timeIntervalSince(debut) }

    /// « Arrêt inattendu à l'écran (pic 38 Mo, durée 2 min 10 s) », pour le journal des erreurs.
    var messageArret: String {
        "Arrêt inattendu à l'écran (pic \(Int(picMo.rounded())) Mo, durée \(Self.texteDuree(duree)))"
    }

    static func texteDuree(_ secondes: TimeInterval) -> String {
        let s = max(0, Int(secondes.rounded()))
        if s < 60 { return "\(s) s" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s" }
        return "\(s / 3600) h \(s % 3600 / 60) min"
    }
}

nonisolated struct JournalSessions: Codable, Equatable, Sendable {
    /// On ne garde que ce qu'affiche le diagnostic (7 jours) avec une marge.
    static let garde: TimeInterval = 8 * 86_400
    static let maxSessions = 300

    /// Du plus ancien au plus récent.
    var sessions: [SessionEcran] = []

    /// Ouvre une session. Renvoie la session précédente si elle était restée ouverte (arrêt inattendu à l'écran),
    /// pour la noter dans le journal des erreurs. Une session déjà ouverte n'est pas rouverte.
    @discardableResult
    mutating func ouvrir(a date: Date, mo: Double) -> SessionEcran? {
        var arretee: SessionEcran?
        if let i = sessions.indices.last, sessions[i].fin == nil, !sessions[i].interrompue {
            sessions[i].interrompue = true
            arretee = sessions[i]
        }
        sessions.append(SessionEcran(debut: date, mo: mo))
        sessions.removeAll { date.timeIntervalSince($0.debut) > Self.garde }
        if sessions.count > Self.maxSessions { sessions.removeFirst(sessions.count - Self.maxSessions) }
        return arretee
    }

    var estOuverte: Bool { indexOuvert != nil }

    var picSessionOuverte: Double? { indexOuvert.map { sessions[$0].picMo } }

    /// Note une mesure. Renvoie vrai si c'est un nouveau pic de la session.
    @discardableResult
    mutating func mesurer(a date: Date, mo: Double) -> Bool {
        guard let i = indexOuvert else { return false }
        sessions[i].derniereMesure = date
        guard mo > sessions[i].picMo else { return false }
        sessions[i].picMo = mo
        return true
    }

    mutating func fermer(a date: Date, mo: Double) {
        guard let i = indexOuvert else { return }
        mesurer(a: date, mo: mo)
        sessions[i].fin = date
    }

    private var indexOuvert: Int? {
        guard let i = sessions.indices.last, sessions[i].fin == nil, !sessions[i].interrompue else { return nil }
        return i
    }

    struct Bilan: Equatable, Sendable {
        var sessions = 0
        var picMo: Double = 0
        var arrets = 0
        var tempsEcran: TimeInterval = 0
    }

    func bilan(depuis date: Date) -> Bilan {
        let liste = sessions.filter { $0.debut >= date }
        return Bilan(sessions: liste.count, picMo: liste.map(\.picMo).max() ?? 0,
                     arrets: liste.filter(\.interrompue).count, tempsEcran: liste.reduce(0) { $0 + $1.duree })
    }

    func arrets(depuis date: Date) -> [SessionEcran] {
        sessions.filter { $0.interrompue && $0.debut >= date }.reversed()
    }
}

/// Quand écrire le journal pendant une session : dès que le pic monte de 1 Mo, sinon au plus toutes les 30 s.
/// Assez souvent pour qu'un arrêt brutal garde des valeurs récentes, assez peu pour ne rien coûter.
nonisolated struct CadenceEcriture: Sendable {
    static let ecart: Double = 1
    static let intervalle: TimeInterval = 30

    private(set) var picEcrit: Double = 0
    private(set) var ecritA = Date.distantPast

    mutating func doitEcrire(a date: Date, pic: Double) -> Bool {
        guard pic - picEcrit >= Self.ecart || date.timeIntervalSince(ecritA) >= Self.intervalle else { return false }
        ecrit(a: date, pic: pic)
        return true
    }

    mutating func ecrit(a date: Date, pic: Double) {
        picEcrit = max(picEcrit, pic)
        ecritA = date
    }

    mutating func reinitialiser() { self = CadenceEcriture() }
}

/// Où est gardé le journal des sessions : l'App Group de l'appareil, un espace à part pour les tests.
nonisolated struct RegistreSessions: Sendable {
    let suite: String
    static let partage = RegistreSessions(suite: Groupes.app)
    private static let cle = "sessionsEcran"

    private var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

    func charger() -> JournalSessions {
        guard let data = defaults.data(forKey: Self.cle) else { return JournalSessions() }
        return (try? JSONDecoder().decode(JournalSessions.self, from: data)) ?? JournalSessions()
    }

    func enregistrer(_ journal: JournalSessions) {
        if let data = Journal.essayer(.stockage, "Enregistrement des sessions à l'écran", { try JSONEncoder().encode(journal) }) {
            defaults.set(data, forKey: Self.cle)
        }
    }

    func effacer() { defaults.removeObject(forKey: Self.cle) }
}
