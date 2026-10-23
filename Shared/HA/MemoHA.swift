import Foundation

/// Mémo de contexte du tri dans Home Assistant : la liste Local To-do « Aiguillage · mémo » (`todo.aiguillage_memo`),
/// une fiche par élément (titre = sujet, description = détails). On l'édite aussi dans HA (panneau Listes de tâches).
/// Utilisé quand les tâches de l'appareil sont dans HA ; sinon, la liste Google Tasks « Relance · mémo ».
/// Appels REST `todo.*` avec le jeton `apps-perso` (pas de file d'attente hors ligne : une fiche s'écrit en ligne).
nonisolated struct MemoHA: Sendable {
    static let entity = "todo.aiguillage_memo"

    struct Fiche: Sendable, Equatable {
        var id: String
        var title: String
        var details: String
    }

    struct Erreur: LocalizedError {
        var status: Int
        var message: String
        var errorDescription: String? { "Home Assistant a répondu \(status) : \(message)" }
    }

    let url: URL
    let token: String

    /// Fiches non retirées, par ordre alphabétique.
    func fiches() async throws -> [Fiche] {
        let reponse = try await call("get_items", ["entity_id": Self.entity, "status": "needs_action"], response: true)
        let items = ((reponse?[Self.entity] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        return items.compactMap { item in
            guard let uid = item["uid"] as? String, let summary = item["summary"] as? String, !summary.isEmpty else { return nil }
            return Fiche(id: uid, title: summary, details: item["description"] as? String ?? "")
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func add(title: String, details: String) async throws {
        var data: [String: Any] = ["entity_id": Self.entity, "item": title]
        if !details.isEmpty { data["description"] = details }
        _ = try await call("add_item", data)
    }

    func update(id: String, title: String, details: String) async throws {
        _ = try await call("update_item", ["entity_id": Self.entity, "item": id, "rename": title, "description": details])
    }

    /// « Retirer » une fiche la coche (elle reste visible, cochée, dans la liste de HA).
    func complete(id: String) async throws {
        _ = try await call("update_item", ["entity_id": Self.entity, "item": id, "status": "completed"])
    }

    /// Ajoute la fiche, ou complète celle du même sujet (même règle que la liste Google).
    func remember(title: String, details: String) async throws -> MemoMerge.Outcome {
        if let fiche = try await fiches().first(where: { MemoMerge.sameSubject($0.title, title) }) {
            guard let merged = MemoMerge.merged(fiche.details, adding: details) else { return .unchanged }
            try await update(id: fiche.id, title: fiche.title, details: merged)
            return .completed
        }
        try await add(title: title, details: details)
        return .added
    }

    /// Un appel peut-il être renvoyé sans risque si la réponse s'est perdue ?
    static func rejouable(_ service: String) -> Bool { service != "add_item" }

    private func call(_ service: String, _ data: [String: Any], response: Bool = false) async throws -> [String: Any]? {
        var components = URLComponents(url: url.appending(path: "api/services/todo/\(service)"), resolvingAgainstBaseURL: false)!
        if response { components.queryItems = [URLQueryItem(name: "return_response", value: nil)] }
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: data)
        // Lire, renommer, cocher : rejouables ; ajouter (`add_item`) non, une fiche ajoutée deux fois serait en double.
        let (body, reponse) = try await Reseau.envoyer(request, rejouable: Self.rejouable(service))
        let status = reponse?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Erreur(status: status, message: String(decoding: body, as: UTF8.self))
        }
        guard response else { return nil }
        return (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["service_response"] as? [String: Any]
    }
}
