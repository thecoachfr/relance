import Foundation

/// Fiche du mémo de contexte : une personne, un lieu, une activité ou une règle de tri.
nonisolated struct MemoEntry: Identifiable, Equatable, Sendable {
    var id: String
    /// « Dentiste », « Place 38 », « Règle : note de frais ».
    var title: String
    /// Détails libres : nom, adresse, téléphone, lien, catégorie et tag habituels…
    var details: String
}

/// Mémo de contexte de la routine de tri : une fiche par élément d'une liste, dans Home Assistant
/// (`todo.aiguillage_memo`, voir `MemoHA`) quand l'appareil y range ses tâches, sinon dans la liste Google Tasks
/// « Relance · mémo ». La routine le lit à chaque tri (lecture seule) ; on l'enrichit depuis l'app, depuis HA
/// ou à la voix. Retirer une fiche la coche (réversible).
@Observable
final class MemoStore {
    static let listTitle = MemoMerge.listTitle
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
        if let ha = MemoHA.current {
            return await run { try await ha.add(title: title, details: details); try await reload() }
        }
        await run {
            _ = try await api().insert(["title": title, "notes": details])
            try await reload()
        }
    }

    /// Ajoute la fiche, ou complète celle du même sujet. `nil` si Google n'a pas répondu.
    @discardableResult
    func remember(title: String, details: String) async -> MemoMerge.Outcome? {
        var outcome: MemoMerge.Outcome?
        if let ha = MemoHA.current {
            await run {
                outcome = try await ha.remember(title: title, details: details)
                try await reload()
            }
            return lastError == nil ? outcome : nil
        }
        await run {
            try await reload()
            if let entry = entries.first(where: { MemoMerge.sameSubject($0.title, title) }) {
                guard let merged = MemoMerge.merged(entry.details, adding: details) else {
                    outcome = .unchanged
                    return
                }
                _ = try await api().patch(id: entry.id, ["notes": merged])
                outcome = .completed
            } else {
                _ = try await api().insert(["title": title, "notes": details])
                outcome = .added
            }
            try await reload()
        }
        return lastError == nil ? outcome : nil
    }

    func update(_ entry: MemoEntry) async {
        if let ha = MemoHA.current {
            return await run { try await ha.update(id: entry.id, title: entry.title, details: entry.details); try await reload() }
        }
        await run {
            _ = try await api().patch(id: entry.id, ["title": entry.title, "notes": entry.details])
            try await reload()
        }
    }

    func remove(_ entry: MemoEntry) async {
        entries.removeAll { $0.id == entry.id }
        if let ha = MemoHA.current { return await run { try await ha.complete(id: entry.id) } }
        await run { _ = try await api().patch(id: entry.id, ["status": "completed"]) }
    }

    private func reload() async throws {
        if let ha = MemoHA.current {
            entries = try await ha.fiches().map { MemoEntry(id: $0.id, title: $0.title, details: $0.details) }
            return
        }
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

extension MemoMerge {
    /// Fiche tirée du lieu d'une tâche : le nom en sujet ; adresse, téléphone, lien,
    /// puis catégorie et tags de la tâche (« catégorie Administratif, tag SCI »).
    static func draft(contact: TaskContact, category: String?, tags: [String]) -> (title: String, details: String) {
        var parts: [String] = []
        if let address = contact.address, address != contact.name { parts.append(address) }
        if let phone = contact.phone { parts.append(phone) }
        if let link = contact.link { parts.append(link.absoluteString) }
        var habits: [String] = []
        if let category { habits.append("catégorie \(category)") }
        if !tags.isEmpty { habits.append((tags.count > 1 ? "tags " : "tag ") + tags.joined(separator: ", ")) }
        if !habits.isEmpty { parts.append(habits.joined(separator: ", ")) }
        return (contact.name, parts.joined(separator: separator))
    }

    /// Fiche tirée d'une tâche quelconque, à retoucher avant d'enregistrer : le titre en sujet ;
    /// les notes (sans les lignes du tri : 🎙, 💡, 🎒), le lieu, la catégorie et les tags en détails.
    static func draft(title: String, notes: String, category: String?, tags: [String]) -> (title: String, details: String) {
        let text = NoteLines.visible(notes).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in !line.isEmpty && !["🎙", "💡", "🎒"].contains { line.hasPrefix($0) } }
            .joined(separator: " ")
        var parts = [text].filter { !$0.isEmpty }
        if let contact = TaskContact(notes: notes) {
            parts.append(String(contact.line.dropFirst(TaskContact.marker.count + 1)).replacingOccurrences(of: " · ", with: ", "))
        }
        let place = draft(contact: TaskContact(name: title), category: category, tags: tags).details
        if !place.isEmpty { parts.append(place) }
        return (title, parts.joined(separator: separator))
    }
}
