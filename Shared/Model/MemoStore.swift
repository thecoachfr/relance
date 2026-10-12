import Foundation

/// Fiche du mémo de contexte : une personne, un lieu, une activité ou une règle de tri.
nonisolated struct MemoEntry: Identifiable, Equatable, Sendable {
    var id: String
    /// « Dentiste », « Place 38 », « Règle : note de frais ».
    var title: String
    /// Détails libres : nom, adresse, téléphone, lien, catégorie et tag habituels…
    var details: String
}

/// Mémo de contexte de la routine de tri, rangé dans une liste Google Tasks à part (« Relance · mémo ») :
/// une tâche par fiche. La routine le lit à chaque tri (lecture seule) ; on l'enrichit depuis l'app,
/// Google Tasks, ou à la voix. Retirer une fiche la coche (réversible dans Google Tasks).
@Observable
final class MemoStore {
    static let listTitle = "Relance · mémo"
    private static let listIDKey = "memoListID"

    private(set) var entries: [MemoEntry] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private let auth: any AccountProvider

    init(auth: any AccountProvider) {
        self.auth = auth
    }

    private func api() async throws -> TasksAPI {
        var api = TasksAPI(token: { [auth] in try await auth.accessToken() })
        if let id = AppGroup.defaults.string(forKey: Self.listIDKey) {
            api.list = id
        } else {
            let id = try await api.listID(named: Self.listTitle)
            AppGroup.defaults.set(id, forKey: Self.listIDKey)
            api.list = id
        }
        return api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await run { try await reload() }
    }

    func add(title: String, details: String) async {
        await run {
            _ = try await api().insert(["title": title, "notes": details])
            try await reload()
        }
    }

    func update(_ entry: MemoEntry) async {
        await run {
            _ = try await api().patch(id: entry.id, ["title": entry.title, "notes": entry.details])
            try await reload()
        }
    }

    func remove(_ entry: MemoEntry) async {
        entries.removeAll { $0.id == entry.id }
        await run { _ = try await api().patch(id: entry.id, ["status": "completed"]) }
    }

    private func reload() async throws {
        let tasks = try await api().fetch(updatedMin: nil)
        entries = tasks.compactMap { task in
            guard let id = task.id, let title = task.title, !title.isEmpty else { return nil }
            return MemoEntry(id: id, title: title, details: task.notes ?? "")
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Liste supprimée ou recréée dans Google Tasks (404) : on oublie son identifiant et on réessaie une fois.
    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
            lastError = nil
        } catch TasksAPIError.http(404, _) {
            AppGroup.defaults.removeObject(forKey: Self.listIDKey)
            do { try await work(); lastError = nil } catch { lastError = error.localizedDescription }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
