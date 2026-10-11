import Foundation
import SwiftData

/// Point d'entrée unique pour lire et modifier les tâches.
/// Chaque modification est enregistrée localement, puis envoyée à Google et suivie d'un recalcul des relances.
@Observable
final class TaskStore {
    let container: ModelContainer
    let auth: GoogleAuth
    let scheduler = ReminderScheduler()
    private(set) var isSyncing = false
    private(set) var lastError: String?
    /// Tâche à ouvrir (touche sur une notification).
    var openedTaskID: UUID?

    private var context: ModelContext { container.mainContext }
    private var api: TasksAPI { TasksAPI(token: { [auth] in try await auth.accessToken() }) }

    private static let lastSyncKey = "lastSync"
    private var lastSync: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncKey) }
    }

    init(auth: GoogleAuth, inMemory: Bool = false) {
        self.auth = auth
        container = try! ModelContainer(
            for: TaskItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    // MARK: - Lecture

    func activeTasks() -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted && !$0.isTrashed })
        return (try? context.fetch(descriptor)) ?? []
    }

    func task(_ id: UUID) -> TaskItem? {
        try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.localID == id })).first
    }

    // MARK: - Actions

    @discardableResult
    func add(title: String, day: Date?, minutes: Int?) -> TaskItem {
        let item = TaskItem(title: title, dueDay: day, dueMinutes: day == nil ? nil : minutes)
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

    func update(_ item: TaskItem, title: String, notes: String, day: Date?, minutes: Int?) {
        item.title = title
        item.notes = notes
        item.dueDay = day.map { Calendar.current.startOfDay(for: $0) }
        item.dueMinutes = day == nil ? nil : minutes
        item.snoozedUntil = nil
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
    }

    // MARK: - Synchronisation Google Tasks

    private var syncTask: Task<Void, Never>?

    /// Une seule synchro à la fois ; un appel pendant une synchro attend la fin puis relance la sienne.
    func sync() async {
        while let running = syncTask { await running.value }
        let task = Task { await performSync() }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func performSync() async {
        guard auth.isSignedIn else { return }
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
            "notes": NotesTimeCodec.encode(minutes: item.dueMinutes, notes: item.notes),
            "due": TasksAPI.due(fromDay: item.dueDay) ?? NSNull(),
            "status": item.isCompleted ? "completed" : "needsAction",
            "completed": item.isCompleted ? TasksAPI.timestamp(item.completedAt ?? .now) : NSNull(),
        ]
    }

    static func apply(_ r: RemoteTask, to item: TaskItem) {
        let (minutes, notes) = NotesTimeCodec.decode(r.notes)
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
