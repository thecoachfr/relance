import Foundation

/// Écriture d'une fiche du mémo directement chez Google, hors de l'app :
/// montre (Siri) et extension de partage « Mémo Aiguillage ».
extension TasksAPI {
    /// L'API positionnée sur la liste du mémo (créée si besoin).
    func onMemoList() async throws -> TasksAPI {
        var api = self
        api.list = try await listID(named: MemoMerge.listTitle)
        return api
    }

    /// Sujets des fiches actuelles, pour proposer de compléter l'une d'elles.
    func memoSubjects() async throws -> [String] {
        try await onMemoList().fetch(updatedMin: nil)
            .filter { $0.status != "completed" }
            .compactMap(\.title).filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Ajoute la fiche, ou complète celle du même sujet (même règle que `MemoStore.remember`).
    func remember(title: String, details: String) async throws -> MemoMerge.Outcome {
        let api = try await onMemoList()
        let entries = try await api.fetch(updatedMin: nil)
        if let entry = entries.first(where: { $0.status != "completed" && MemoMerge.sameSubject($0.title ?? "", title) }),
           let id = entry.id {
            guard let merged = MemoMerge.merged(entry.notes ?? "", adding: details) else { return .unchanged }
            _ = try await api.patch(id: id, ["notes": merged])
            return .completed
        }
        _ = try await api.insert(["title": title, "notes": details])
        return .added
    }
}
