import DonneesHA
import Foundation
import SwiftData
import WidgetKit

/// Point d'entrée unique pour lire et modifier les tâches.
/// Chaque modification est enregistrée localement, puis envoyée (Home Assistant, ou Google Tasks tant que HA
/// n'est pas activé sur l'appareil) et suivie d'un recalcul des relances.
@Observable
final class TaskStore {
    let container: ModelContainer
    let auth: any AccountProvider
    let scheduler = ReminderScheduler()
    /// Mémo de contexte de la routine de tri (liste Google Tasks à part).
    @ObservationIgnored lazy var memo = MemoStore(auth: auth)
    var isSyncing = false
    var lastError: String?
    /// Tâche à ouvrir (touche sur une notification).
    var openedTaskID: UUID?
    /// Ouvre la saisie rapide (commande du Centre de contrôle).
    var showQuickAdd = false
    /// Appelé après chaque changement des tâches (activité en direct, côté app).
    var onTasksChanged: (() -> Void)?
    /// Temps de trajet jusqu'à l'adresse d'une tâche (Plans, côté app) ; `nil` = pas de « Pars maintenant ».
    var travelMinutes: ((TaskItem) async -> Int?)?
    /// Données d'exemple, sans réseau (captures d'écran, revue de design).
    var isDemo = false
    /// Synchroniseur Home Assistant (espace `aiguillage`), créé à la première synchro une fois HA activé.
    var synchro: Synchroniseur?
    /// Mes abonnements (Réglages › Relances), lus et écrits dans HA (`Subscriptions.haKey`).
    var subscriptions: [String] = Subscriptions.cached()
    /// Recettes d'actions (Réglages › Actions automatiques), lues et écrites dans HA (`Recette.haKey`).
    var recettes: [Recette] = []
    /// Forcé par les tests, sans toucher au réglage partagé de l'appareil (que l'app hôte lit aussi).
    var haActiveOverride: Bool?
    /// Coupé par les tests de synchro : le centre de notifications du simulateur peut bloquer des dizaines de secondes.
    var schedulesReminders = true
    /// Crée le synchroniseur (remplacé dans les tests par un faux Home Assistant).
    var makeSynchroniser: () async -> Synchroniseur? = { await HAConfig.makeSynchroniser(withFallback: true) }

    var context: ModelContext { container.mainContext }
    var api: TasksAPI { TasksAPI(token: { [auth] in try await auth.accessToken() }) }

    /// v2 : la base a déménagé dans l'App Group, il faut une synchro complète.
    private static let lastSyncKey = "lastSync.v2"
    var lastSync: Date? {
        get { AppGroup.defaults.object(forKey: Self.lastSyncKey) as? Date }
        set { AppGroup.defaults.set(newValue, forKey: Self.lastSyncKey) }
    }

    init(auth: any AccountProvider, inMemory: Bool = false) {
        self.auth = auth
        container = AppGroup.modelContainer(inMemory: inMemory)
    }

    // MARK: - Lecture

    /// Tags connus : ceux de départ, puis ceux trouvés dans les tâches (ordre alphabétique).
    func knownTags() -> [String] {
        let used = activeTasks().flatMap(\.tags)
        var seen = Set(TaskTag.defaults.map { $0.lowercased() })
        let extra = used.filter { seen.insert($0.lowercased()).inserted }.sorted()
        return TaskTag.defaults + extra
    }

    func activeTasks() -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted && !$0.isTrashed })
        return (try? context.fetch(descriptor)) ?? []
    }

    func task(googleID: String) -> TaskItem? {
        try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.googleID == googleID })).first
    }

    func task(_ id: UUID) -> TaskItem? {
        try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.localID == id })).first
    }

    // MARK: - Actions

    @discardableResult
    func add(title: String, day: Date?, minutes: Int?, category: String? = nil, priority: TaskPriority = .normal,
             notes: String = "") -> TaskItem {
        let item = TaskItem(title: title, notes: notes, dueDay: day, dueMinutes: day == nil ? nil : minutes)
        item.category = category
        item.priority = priority
        context.insert(item)
        commit()
        return item
    }

    func complete(_ item: TaskItem) {
        item.isCompleted = true
        item.completedAt = .now
        item.snoozedUntil = nil
        item.markChanged()
        spawnNext(of: item)
        commit()
    }

    func reopen(_ item: TaskItem) {
        item.isCompleted = false
        item.completedAt = nil
        // « Annuler » juste après « Fait » : la suivante d'une récurrente n'a plus lieu d'être.
        if let nextID = spawned.removeValue(forKey: item.localID), let next = task(nextID), !next.isCompleted {
            next.isTrashed = true
            next.markChanged()
            item.notes = item.notes.components(separatedBy: "\n").filter { $0 != Recurrence.spawnedMarker }.joined(separator: "\n")
        }
        item.markChanged()
        commit()
    }

    // MARK: - Récurrence

    /// Suivantes créées pendant cette session (pour « Annuler »).
    private var spawned: [UUID: UUID] = [:]
    /// Suivante créée pendant la lecture de Google : à envoyer sans attendre la synchro suivante.
    var spawnedDuringPull = false

    /// Crée la tâche suivante d'une récurrente (ligne 🔄) et marque celle-ci « ↪ Suivante créée »,
    /// pour qu'aucun autre appareil ne la recrée.
    @discardableResult
    func spawnNext(of item: TaskItem) -> TaskItem? {
        guard let rule = Recurrence(notes: item.notes), let due = item.dueDay,
              !item.notes.contains(Recurrence.spawnedMarker) else { return nil }
        // Sans l'agenda (événement propre à la tâche faite) ni la suggestion du tri.
        let notes = item.notes.components(separatedBy: "\n").filter {
            !$0.hasPrefix("📅 Dans l'agenda") && !$0.hasPrefix("💡") && !$0.hasPrefix("➕") && $0 != Recurrence.spawnedMarker
        }.joined(separator: "\n")
        let next = TaskItem(title: item.title, notes: notes,
                            dueDay: rule.nextDay(after: due, done: item.completedAt ?? .now), dueMinutes: item.dueMinutes)
        next.category = item.category
        next.priority = item.priority
        next.tags = item.tags
        next.remindersRaw = item.remindersRaw
        context.insert(next)
        item.notes = (item.notes.isEmpty ? "" : item.notes + "\n") + Recurrence.spawnedMarker
        item.markChanged()
        spawned[item.localID] = next.localID
        return next
    }

    /// Reporte les relances sans toucher à l'échéance.
    func snooze(_ item: TaskItem, until date: Date) {
        item.snoozedUntil = date
        try? context.save()
        Task { await reschedule() }
    }

    /// « Demain matin » : déplace l'échéance au lendemain et relance à l'heure du matin.
    func moveToTomorrow(_ item: TaskItem, now: Date = .now) {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let morning = scheduler.settings.morning
        item.dueDay = tomorrow
        item.snoozedUntil = calendar.date(bySettingHour: morning / 60, minute: morning % 60, second: 0, of: tomorrow)
        item.markChanged()
        commit()
    }

    func update(_ item: TaskItem, title: String, notes: String, day: Date?, minutes: Int?, category: String?? = .none,
                priority: TaskPriority? = nil, reminders: ReminderOverride?? = .none, tags: [String]? = nil) {
        item.title = title
        if let category { item.category = category }
        if let priority { item.priority = priority }
        if let reminders { item.reminderOverride = reminders }
        if let tags { item.tags = tags }
        item.notes = notes
        item.dueDay = day.map { Calendar.current.startOfDay(for: $0) }
        item.dueMinutes = day == nil ? nil : minutes
        item.snoozedUntil = nil
        item.markChanged()
        commit()
    }

    /// Crée la tâche proposée par le tri (ligne « ➕ ») avec la catégorie de la tâche d'origine, puis retire la
    /// ligne. `create` faux : la proposition est seulement retirée (« Ignorer »).
    @discardableResult
    func resolveProposal(of item: TaskItem, create: Bool) -> TaskItem? {
        guard let proposal = TaskProposal(notes: item.notes) else { return nil }
        let created = create ? add(title: proposal.title, day: proposal.startDay(), minutes: proposal.minutes,
                                   category: item.category, notes: proposal.notes) : nil
        item.notes = TaskProposal.removing(from: item.notes)
        item.markChanged()
        commit()
        return created
    }

    // MARK: - Actions (P9-D1)

    /// Ajoute, remplace (même `id`) ou retire des actions ; synchronisé comme le reste de la tâche.
    func setActions(_ actions: [TacheHA.Action], of item: TaskItem) {
        guard actions != item.actions else { return }
        item.actions = actions
        item.markChanged()
        commit()
    }

    func addAction(_ action: TacheHA.Action, to item: TaskItem) {
        setActions(item.actions.filter { $0.id != action.id } + [action], of: item)
    }

    func removeAction(id: String, from item: TaskItem) {
        setActions(item.actions.filter { $0.id != id }, of: item)
    }

    /// Note l'état d'une action (et son résultat), horodaté.
    func markAction(id: String, of item: TaskItem, etat: String, resultat: String?, now: Date = .now) {
        var actions = item.actions
        guard let i = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[i].etat = etat
        actions[i].resultat = resultat
        actions[i].maj = TacheHA.timestamp(now)
        setActions(actions, of: item)
    }

    /// Avant un retri par la routine : sans catégorie ni tags, elle traite la tâche comme neuve.
    func clearTriage(_ items: [TaskItem]) {
        for item in items where item.category != nil || !item.tags.isEmpty {
            item.category = nil
            item.tags = []
            item.markChanged()
        }
        commit()
    }

    func setPriority(_ item: TaskItem, _ priority: TaskPriority) {
        guard item.priority != priority else { return }
        item.priority = priority
        item.markChanged()
        commit()
    }

    func setTime(_ item: TaskItem, minutes: Int) {
        item.dueMinutes = minutes
        item.snoozedUntil = nil
        item.markChanged()
        commit()
    }

    func delete(_ item: TaskItem) {
        item.isTrashed = true
        item.markChanged()
        commit()
    }

    private func commit() {
        try? context.save()
        Task {
            await reschedule()
            await sync()
        }
    }

    // MARK: - Relances

    func reschedule() async {
        guard schedulesReminders else { return }
        let tasks = activeTasks()
        let inbox = tasks.filter { $0.dueDay == nil && $0.toSee == nil }.count
        let completedIDs = Set(((try? context.fetch(FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.isCompleted || $0.isTrashed }))) ?? []).map(\.localID.uuidString))
        let overdue = tasks.filter { $0.isOverdue() }.count
        var plannables: [PlannableTask] = []
        for item in tasks {
            var p = item.plannable()
            if let travelMinutes, let due = item.dueInstant(), item.dueMinutes != nil,
               due > .now, due.timeIntervalSinceNow < 36 * 3600 {
                p.travelMinutes = await travelMinutes(item)
            }
            plannables.append(p)
        }
        await scheduler.apply(tasks: plannables, inboxCount: inbox,
                              finishedTaskIDs: completedIDs, overdueNow: overdue)
        WidgetCenter.shared.reloadAllTimelines()
        onTasksChanged?()
    }

    // MARK: - Synchronisation Google Tasks

    private var syncTask: Task<Void, Never>?
    /// Arrivées de Google pendant la dernière synchro avec une date mais sans heure.
    var needTimeNow: [UUID] = []

    /// Une seule synchro à la fois ; un appel pendant une synchro attend la fin puis relance la sienne.
    func sync() async {
        while let running = syncTask { await running.value }
        // La tâche se retire elle-même avant de se terminer : un appel en attente qui reprend
        // ne retombe jamais sur une synchro déjà finie (sinon il boucle sans fin sur le thread principal).
        let task = Task {
            await performSync()
            syncTask = nil
        }
        syncTask = task
        await task.value
    }

    private func performSync() async {
        if isHAActive, !isDemo {
            await performHASync()
            return await afterSync()
        }
        guard auth.isSignedIn, !isDemo else {
            if isDemo { await reschedule() }
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await push()
            try await pull()
            if spawnedDuringPull {
                spawnedDuringPull = false
                try await push()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        try? context.save()
        await afterSync()
    }

    /// Relances recalculées, puis question « À quelle heure ? » pour les tâches arrivées datées sans heure.
    private func afterSync() async {
        await reschedule()
        if !needTimeNow.isEmpty {
            // Selon le profil de la priorité (une tâche Basse ne demande pas d'heure, d'origine).
            let asks = needTimeNow.compactMap { task($0) }
                .filter { $0.dueMinutes == nil && !$0.isCompleted && scheduler.settings[$0.priority].askTime }
            needTimeNow = []
            await scheduler.askTimeNow(for: asks.map { $0.plannable() })
        }
    }

    /// Partagées depuis une autre app sans réseau (extension) : elles deviennent des tâches à envoyer.
    func insertPendingShares() {
        for shared in PendingShares.takeAll() {
            let item = TaskItem(title: shared.title, notes: shared.notes, dueDay: shared.day,
                                dueMinutes: shared.day == nil ? nil : shared.minutes)
            item.priority = shared.priority
            context.insert(item)
        }
    }

    private func push() async throws {
        insertPendingShares()
        let dirty = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDirty }))
        for item in dirty {
            if item.isTrashed {
                if let id = item.googleID { try await api.delete(id: id) }
                context.delete(item)
                continue
            }
            let fields = Self.fields(for: item)
            let remote = if let id = item.googleID {
                try await api.patch(id: id, fields)
            } else {
                try await api.insert(fields)
            }
            item.googleID = remote.id
            item.isDirty = false
        }
        try context.save()
    }

    private func pull() async throws {
        let started = Date.now
        let since = lastSync?.addingTimeInterval(-60)
        let remote = try await api.fetch(updatedMin: since)
        let all = try context.fetch(FetchDescriptor<TaskItem>())
        var byGoogleID = Dictionary(all.compactMap { item in item.googleID.map { ($0, item) } },
                                    uniquingKeysWith: { first, _ in first })

        for r in remote {
            guard let id = r.id else { continue }
            let local = byGoogleID[id]
            if local?.isDirty == true { continue }
            let wasDone = local?.isCompleted ?? true

            if r.deleted == true {
                if let local { context.delete(local) }
                continue
            }
            let item = local ?? {
                let new = TaskItem(title: "")
                new.googleID = id
                context.insert(new)
                byGoogleID[id] = new
                return new
            }()
            Self.apply(r, to: item)
            // Cochée ailleurs (montre, Google) : seul l'appareil qui relance crée la suivante d'une récurrente.
            if !wasDone, item.isCompleted, ReminderScheduler.isEnabledOnThisDevice, spawnNext(of: item) != nil {
                spawnedDuringPull = true
            }
            // Pas à la première synchro complète : on ne questionne que les tâches qui viennent d'arriver.
            if local == nil, since != nil, !item.isCompleted, item.dueDay != nil, item.dueMinutes == nil {
                needTimeNow.append(item.localID)
            }
        }

        // Synchro complète : ce qui n'est plus renvoyé a été coché ou supprimé ailleurs.
        if since == nil {
            let remoteIDs = Set(remote.compactMap(\.id))
            for item in all where !item.isDirty && !item.isCompleted {
                if let id = item.googleID, !remoteIDs.contains(id) { context.delete(item) }
            }
        }
        try context.save()
        lastSync = started
    }

    static func fields(for item: TaskItem) -> [String: Any] {
        [
            "title": item.title,
            "notes": NotesTimeCodec.encode(minutes: item.dueMinutes, category: item.category, tags: item.tags,
                                           priority: item.priority, reminders: item.reminderOverride, notes: item.notes),
            "due": TasksAPI.due(fromDay: item.dueDay) ?? NSNull(),
            "status": item.isCompleted ? "completed" : "needsAction",
            "completed": item.isCompleted ? TasksAPI.timestamp(item.completedAt ?? .now) : NSNull(),
        ]
    }

    static func apply(_ r: RemoteTask, to item: TaskItem) {
        let meta = NotesTimeCodec.decode(r.notes)
        let (minutes, notes) = (meta.minutes, meta.notes)
        item.category = meta.category
        item.priority = meta.priority
        item.tags = meta.tags
        item.remindersRaw = meta.reminders?.line
        let day = TasksAPI.day(fromDue: r.due)
        if day != item.dueDay || minutes != item.dueMinutes { item.snoozedUntil = nil }
        item.title = r.title ?? ""
        item.notes = notes
        item.dueDay = day
        item.dueMinutes = day == nil ? nil : minutes
        item.isCompleted = r.status == "completed"
        item.completedAt = TasksAPI.parse(r.completed)
        item.updatedAt = TasksAPI.parse(r.updated) ?? .now
        item.isDirty = false
    }

    func signOut() {
        auth.signOut()
        // Les tâches sont dans HA : la connexion Google ne sert plus qu'au mémo.
        guard !isHAActive else { return }
        try? context.delete(model: TaskItem.self)
        try? context.save()
        lastSync = nil
        Task { await reschedule() }
    }
}
