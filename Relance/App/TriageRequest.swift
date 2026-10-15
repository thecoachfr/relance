import DonneesHA
import Foundation

/// « Retrier avec Claude » : la tâche perd sa catégorie et ses tags, puis la routine de tri est réveillée
/// (webhook Home Assistant, action « triage ») et la reclasse comme une tâche neuve, avec le mémo.
/// Priorité, relances propres (🔁) et contact (📍) ne bougent pas.
enum TriageRequest {
    @MainActor static func retriage(_ items: [TaskItem], store: TaskStore) async -> Bool {
        store.clearTriage(items)
        await store.sync()          // HA (ou Google) doit avoir la tâche sans catégorie avant que la routine la lise.
        guard store.lastError == nil, let url = PushRegistration.webhookURL else { return false }
        // Hors ligne, la tâche n'est encore que dans l'outbox : la routine ne la verrait pas.
        if store.isHAActive, store.synchro?.etat != .aJour { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "triage"])
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
