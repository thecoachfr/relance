import Foundation
import SwiftData
import WidgetKit

/// Point d'entrée unique pour lire et modifier les tâches.
/// Chaque modification est enregistrée localement, puis envoyée à Google et suivie d'un recalcul des relances.
@Observable
final class TaskStore {
    let container: ModelContainer
    let auth: any AccountProvider
    let scheduler = ReminderScheduler()
    private(set) var isSyncing = false
    private(set) var lastError: String?
    /// Tâche à ouvrir (touche sur une notification).
    var openedTaskID: UUID?
    /// Ouvre la saisie rapide (commande du Centre de contrôle).
    var showQuickAdd = false
    /// Appelé après chaque changement des tâches (activité en direct, côté app).
    var onTasksChanged: (() -> Void)?
    /// Données d'exemple, sans réseau (captures d'écran, revue de design).
    var isDemo = false

    private var context: ModelContext { container.mainContext }
    private var api: TasksAPI { TasksAPI(token: { [auth] in try await auth.accessToken() }) }

    /// v2 : la base a déménagé dans l'App Group, il faut une synchro complète.
    private static let lastSyncKey = "lastSync.v2"
    private var lastSync: Date? {
        get { AppGroup.defaults.object(forKey: Self.lastSyncKey) as? Date }
        set { AppGroup.defaults.set(newValue, forKey: Self.lastSyncKey) }
    }

    init(auth: any AccountProvider, inMemory: Bool = false) {
        self.auth = auth
        container = AppGroup.modelContainer(inMemory: inMemory)
    }

    // MARK: - Lecture

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
    func add(title: String, day: Date?, minutes: Int?, category: String? = nil, priority: TaskPriority = .normal) -> TaskItem {
        let item = TaskItem(title: title, dueDay: day, dueMinutes: day == nil ? nil : minutes)
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
        commit()
    }

    func reopen(_ item: TaskItem) {
        item.isCompleted = false
        item.completedAt = nil
        item.markChanged()
        commit()
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
                priority: TaskPriority? = nil) {
        item.title = title
        if let category { item.category = category }
        if let priority { item.priority = priority }
        item.notes = notes
        item.dueDay = day.map { Calendar.current.startOfDay(for: $0) }
        item.dueMinutes = day == nil ? nil : minutes
        item.snoozedUntil = nil
        item.markChanged()
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
        let tasks = activeTasks()
        let inbox = tasks.filter { $0.dueDay == nil }.count
        let completedIDs = Set(((try? context.fetch(FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.isCompleted || $0.isTrashed }))) ?? []).map(\.localID.uuidString))
        let overdue = tasks.filter { $0.isOverdue() }.count
        await scheduler.apply(tasks: tasks.map { $0.plannable() }, inboxCount: inbox,
                              finishedTaskIDs: completedIDs, overdueNow: overdue)
        WidgetCenter.shared.reloadAllTimelines()
        onTasksChanged?()
    }

    // MARK: - Synchronisation Google Tasks

    private var syncTask: Task<Void, Never>?
    /// Arrivées de Google pendant la dernière synchro avec une date mais sans heure.
    private var needTimeNow: [UUID] = []

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
        guard auth.isSignedIn, !isDemo else {
            if isDemo { await reschedule() }
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await push()
            try await pull()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        try? context.save()
        await reschedule()
        if !needTimeNow.isEmpty {
            // Une tâche Basse n'a pas besoin d'heure : elle n'est relancée que dans le résumé du matin.
            let asks = needTimeNow.compactMap { task($0) }
                .filter { $0.dueMinutes == nil && !$0.isCompleted && $0.priority != .low }
            needTimeNow = []
            await scheduler.askTimeNow(for: asks.map { $0.plannable() })
        }
    }

    private func push() async throws {
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
            "notes": NotesTimeCodec.encode(minutes: item.dueMinutes, category: item.category,
                                           priority: item.priority, notes: item.notes),
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
        try? context.delete(model: TaskItem.self)
        try? context.save()
        lastSync = nil
        Task { await reschedule() }
    }
}
