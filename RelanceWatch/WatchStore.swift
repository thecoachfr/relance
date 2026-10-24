import Foundation
import Observation
import Security
import WatchConnectivity
import WidgetKit

/// Côté montre. Avec la connexion Google reçue de l'iPhone, la montre lit, coche et ajoute
/// directement dans Google Tasks (en 4G si besoin) ; sinon elle passe par l'iPhone.
/// Les actions s'appliquent tout de suite à l'écran.
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    /// Une seule instance : l'app et Siri (`WatchAddTaskIntent`) partagent la même liste.
    static let shared = WatchStore()
    static let snapshotKey = "watchTasks"
    private static let updatedKey = "watchTasksUpdated"
    /// Partagé avec la complication (même identifiant d'App Group que sur l'iPhone, conteneur propre à la montre).
    static let defaults = Groupes.defaults

    private(set) var tasks: [WatchTask] = WatchStore.loadSnapshot()
    private(set) var lastUpdate: Date? = WatchStore.defaults.object(forKey: WatchStore.updatedKey) as? Date
    private(set) var isRefreshing = false
    private static let tasksInHAKey = "watchTasksInHA"
    /// Tâches dans Home Assistant (dit par l'iPhone) : lecture, coche, ajout et mémo passent par l'iPhone.
    var tasksInHA: Bool { Self.defaults.bool(forKey: Self.tasksInHAKey) }
    private static let lieuxKey = "watchLieuTravail"
    /// Libellés des jours travaillés reçus de l'iPhone (P9-N2), par date.
    private(set) var lieuxTravail: [String: String] = WatchLink.decodeLieux(WatchStore.defaults.data(forKey: WatchStore.lieuxKey))

    let google = GoogleRefreshSession()
    private var api: TasksAPI { TasksAPI(token: { [google] in try await google.validAccessToken() }) }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Lecture directe chez Google

    /// Recharge la liste depuis Google. Sans connexion Google, on garde la dernière liste de l'iPhone.
    func refreshFromGoogle() async {
        guard google.isAvailable, !tasksInHA, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let remote = await Journal.essayer(.reseau, "Lecture de Google Tasks (montre)", {
            try await api.fetch(updatedMin: nil) }) else { return }
        receive(remote.compactMap(Self.watchTask))
    }

    /// Même conventions que l'iPhone : date seule = fin du jour, heure dans la première ligne des notes.
    private static func watchTask(_ r: RemoteTask) -> WatchTask? {
        guard let id = r.id, r.status != "completed", r.deleted != true else { return nil }
        let calendar = Calendar.current
        let meta = NotesTimeCodec.decode(r.notes)
        let minutes = meta.minutes
        let due = TasksAPI.day(fromDue: r.due).flatMap { day -> Date? in
            if let minutes {
                return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
            }
            return calendar.date(byAdding: .day, value: 1, to: day)
        }
        return WatchTask(id: id, title: r.title ?? "", due: due, hasTime: minutes != nil && due != nil, snoozedUntil: nil,
                         priority: meta.priority, category: meta.category,
                         tags: meta.tags.isEmpty ? nil : meta.tags)
    }

    // MARK: - Actions

    func complete(_ task: WatchTask) {
        tasks.removeAll { $0.id == task.id }
        save()
        // Prévient aussi l'iPhone (tout de suite s'il est là, plus tard sinon) pour couper ses relances.
        send([WatchLink.actionKey: WatchLink.Action.complete.rawValue, WatchLink.idKey: task.id])
        guard google.isAvailable, !tasksInHA, UUID(uuidString: task.id) == nil else { return }
        Task {
            await Journal.essayer(.reseau, "Tâche cochée sur Google (montre)") {
                try await api.patch(id: task.id, ["status": "completed", "completed": TasksAPI.timestamp(.now)])
            }
        }
    }

    /// Coche un article d'une liste (P9-G2) : tout de suite à l'écran, puis par l'iPhone vers Home Assistant (file
    /// d'attente s'il n'est pas joignable). Tout coché : la tâche quitte la liste, comme « Fait ».
    func setArticle(_ article: WatchArticle, coche: Bool, of task: WatchTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }),
              let j = tasks[i].articles?.firstIndex(where: { $0.id == article.id }) else { return }
        tasks[i].articles?[j].coche = coche
        if let articles = tasks[i].articles, articles.allSatisfy(\.coche) { tasks.remove(at: i) }
        save()
        send([WatchLink.actionKey: WatchLink.Action.article.rawValue, WatchLink.idKey: task.id,
              WatchLink.articleKey: article.id, WatchLink.cocheKey: coche, WatchLink.dueKey: Date.now])
    }

    /// Le report n'existe que dans les notifications de l'iPhone : il passe toujours par lui.
    func snooze(_ task: WatchTask) {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i].snoozedUntil = .now.addingTimeInterval(3600)
            save()
        }
        send([WatchLink.actionKey: WatchLink.Action.snooze.rawValue, WatchLink.idKey: task.id])
    }

    /// `due` : début du jour (date seule) ou instant précis (avec heure).
    /// Fiche du mémo de tri, écrite directement chez Google (même règle que l'iPhone : un même sujet est complété).
    func remember(title: String, details: String) async throws -> MemoMerge.Outcome {
        try await api.remember(title: title, details: details)
    }

    /// Tâches dans HA : la fiche part à l'iPhone, qui l'enregistre dans le mémo de HA. Réponse de l'iPhone s'il est
    /// joignable ; sinon `nil`, et la fiche attend dans la file de WatchConnectivity (livrée dès qu'il revient) ;
    /// `.some(nil)` si elle n'a pas pu partir du tout.
    func rememberViaPhone(title: String, details: String) async -> MemoMerge.Outcome?? {
        // D'abord directement dans Home Assistant (réseau de la montre), comme l'app.
        if let ha = WatchHA.memo, let outcome = try? await ha.remember(title: title, details: details) {
            return .some(outcome)
        }
        let message: [String: Any] = [WatchLink.actionKey: WatchLink.Action.memo.rawValue,
                                      WatchLink.titleKey: title, WatchLink.detailsKey: details]
        let session = WCSession.default
        // Siri lance souvent la montre à froid : la session s'active et le lien avec l'iPhone revient en un instant.
        for _ in 0..<30 where session.activationState != .activated || !session.isReachable {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Session toujours inactive : impossible même de mettre la fiche en file d'attente.
        guard session.activationState == .activated else { return .some(nil) }
        guard session.isReachable else {
            session.transferUserInfo(message)
            return nil
        }
        let reponse: String? = await withCheckedContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                continuation.resume(returning: reply[WatchLink.outcomeKey] as? String)
            }, errorHandler: { _ in
                session.transferUserInfo(message)
                continuation.resume(returning: nil)
            })
        }
        switch reponse {
        case "added": return .some(.added)
        case "completed": return .some(.completed)
        case "unchanged": return .some(.unchanged)
        case "failed": return .some(nil)
        default: return nil
        }
    }

    func add(title: String, due: Date?, hasTime: Bool, priority: TaskPriority = .normal) {
        Task { await insert(title: title, due: due, hasTime: hasTime, priority: priority) }
    }

    /// Version qu'on peut attendre (Siri répond une fois la tâche partie).
    func insert(title: String, due: Date?, hasTime: Bool, priority: TaskPriority = .normal) async {
        guard google.isAvailable, !tasksInHA else { return sendAdd(title: title, due: due, hasTime: hasTime, priority: priority) }
        let calendar = Calendar.current
        let minutes = hasTime ? due.map {
            let c = calendar.dateComponents([.hour, .minute], from: $0)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        } : nil
        let fields: [String: Any] = [
            "title": title,
            "notes": NotesTimeCodec.encode(minutes: minutes, priority: priority, notes: ""),
            "due": TasksAPI.due(fromDay: due) ?? NSNull(),
        ]
        if await Journal.essayer(.reseau, "Ajout sur Google (montre)", { try await api.insert(fields) }) != nil {
            await refreshFromGoogle()
        } else {
            sendAdd(title: title, due: due, hasTime: hasTime, priority: priority)
        }
    }

    private func sendAdd(title: String, due: Date?, hasTime: Bool, priority: TaskPriority = .normal) {
        var message: [String: Any] = [
            WatchLink.actionKey: WatchLink.Action.add.rawValue,
            WatchLink.titleKey: title,
            WatchLink.hasTimeKey: hasTime,
            WatchLink.priorityKey: priority.rawValue,
        ]
        if let due { message[WatchLink.dueKey] = due }
        send(message)
    }

    /// Message direct si l'iPhone répond, sinon file d'attente livrée dès qu'il redevient joignable.
    private func send(_ message: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in session.transferUserInfo(message) }
        } else {
            session.transferUserInfo(message)
        }
    }

    // MARK: - Réception depuis l'iPhone

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let payload = Payload(applicationContext)
        Task { @MainActor in self.apply(payload) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = Payload(userInfo)
        Task { @MainActor in self.apply(payload) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let payload = Payload(session.receivedApplicationContext)
        Task { @MainActor in self.apply(payload) }
    }

    private func apply(_ payload: Payload) {
        if let token = payload.refreshToken, let clientID = payload.clientID {
            google.store(refreshToken: token, clientID: clientID)
        }
        if let inHA = payload.tasksInHA { Self.defaults.set(inHA, forKey: Self.tasksInHAKey) }
        if let url = payload.haURL, let token = payload.haToken { WatchHA.store(url: url, token: token) }
        if let lieux = payload.lieuxTravail {
            Self.defaults.set(lieux, forKey: Self.lieuxKey)
            let decodes = WatchLink.decodeLieux(lieux)
            if decodes != lieuxTravail { lieuxTravail = decodes }
        }
        if let tasks = payload.tasks { receive(tasks) }
    }

    private func receive(_ tasks: [WatchTask]) {
        let change = tasks != self.tasks
        self.tasks = tasks
        lastUpdate = .now
        save(rechargerComplication: change)
    }

    // MARK: - Copie locale (partagée avec la complication)

    /// La complication n'est rechargée que si les tâches ont changé : watchOS limite durement ses rechargements.
    private func save(rechargerComplication: Bool = true) {
        Self.defaults.set(WatchLink.encode(tasks), forKey: Self.snapshotKey)
        Self.defaults.set(lastUpdate, forKey: Self.updatedKey)
        if rechargerComplication { WidgetCenter.shared.reloadAllTimelines() }
    }

    static func loadSnapshot() -> [WatchTask] {
        WatchLink.decode(defaults.data(forKey: snapshotKey))
    }
}

/// Contenu d'un envoi de l'iPhone, extrait hors du fil principal (types plist uniquement).
nonisolated private struct Payload: Sendable {
    var tasks: [WatchTask]?
    var refreshToken: String?
    var clientID: String?
    var tasksInHA: Bool?
    var haURL: String?
    var haToken: String?
    var lieuxTravail: Data?

    init(_ dictionary: [String: Any]) {
        lieuxTravail = dictionary[WatchLink.lieuTravailKey] as? Data
        haURL = dictionary[WatchLink.haURLKey] as? String
        haToken = dictionary[WatchLink.haTokenKey] as? String
        tasksInHA = dictionary[WatchLink.tasksInHAKey] as? Bool
        tasks = (dictionary[WatchLink.tasksKey] as? Data).map { WatchLink.decode($0) }
        refreshToken = dictionary[WatchLink.refreshTokenKey] as? String
        clientID = dictionary[WatchLink.clientIDKey] as? String
    }
}

/// URL de Home Assistant (préférences de la montre) et jeton apps-perso (trousseau de la montre), reçus de l'iPhone.
nonisolated enum WatchHA {
    private static let urlKey = "haURL"
    private static let service = "fr.alexandrefau.relance.ha"
    private static var defaults: UserDefaults { Groupes.defaults }

    static var memo: MemoHA? {
        guard let texte = defaults.string(forKey: urlKey), let url = URL(string: texte),
              let token = token(), !token.isEmpty else { return nil }
        return MemoHA(url: url, token: token)
    }

    /// Chaînes vides : l'iPhone n'est plus en mode HA, on oublie tout.
    static func store(url: String, token: String) {
        guard !url.isEmpty, !token.isEmpty else {
            defaults.removeObject(forKey: urlKey)
            SecItemDelete(query as CFDictionary)
            return
        }
        defaults.set(url, forKey: urlKey)
        guard self.token() != token else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    private static func token() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
