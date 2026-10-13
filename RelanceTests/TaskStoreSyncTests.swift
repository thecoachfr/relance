import Foundation
import Testing
@testable import Relance

/// Compte factice : connecté, mais le jeton arrive lentement puis échoue (simule le réseau).
final class SlowAccount: AccountProvider {
    var isSignedIn: Bool { true }
    func accessToken() async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        throw TasksAPIError.notSignedIn
    }
    func signOut() {}
    var watchCredentials: (refreshToken: String, clientID: String)? { nil }
}

@MainActor
struct TaskStoreSyncTests {
    /// Deux synchros simultanées (lancement + retour au premier plan) ne doivent pas bloquer l'app.
    @Test(.timeLimit(.minutes(1)))
    func overlappingSyncsFinish() async {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        async let first: Void = store.sync()
        async let second: Void = store.sync()
        async let third: Void = store.sync()
        _ = await (first, second, third)
        #expect(!store.isSyncing)
        #expect(store.lastError != nil)
    }
}

struct ReminderSchedulerTimeoutTests {
    /// iOS ne répond parfois jamais aux appels de ménage des notifications : la synchro ne doit pas rester bloquée.
    @Test(.timeLimit(.minutes(1)))
    func timeoutReturnsEvenIfOperationNeverFinishes() async {
        let start = Date.now
        await ReminderScheduler.withTimeout(seconds: 0.5) {
            try? await Task.sleep(for: .seconds(3600))  // ne répond pas à temps
        }
        #expect(Date.now.timeIntervalSince(start) < 5)
    }
}

@MainActor
struct RecurringTaskTests {
    /// « Fait » sur une tâche récurrente : la suivante est créée (même heure, catégorie, lieu),
    /// la tâche faite est marquée, et « Annuler » retire la suivante.
    @Test func completingCreatesTheNextOne() throws {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let item = store.add(title: "Envoyer les quittances", day: today, minutes: 9 * 60, category: "Administratif")
        item.notes = "📍 Mairie · 1 place de la Mairie, 75002 Paris\n" + Recurrence.daily(every: 2).line

        store.complete(item)
        let next = try #require(store.activeTasks().first { $0.title == "Envoyer les quittances" })
        #expect(next.dueDay == calendar.date(byAdding: .day, value: 2, to: today))
        #expect(next.dueMinutes == 9 * 60 && next.category == "Administratif")
        #expect(Recurrence(notes: next.notes) == .daily(every: 2))
        #expect(TaskContact(notes: next.notes)?.name == "Mairie")
        #expect(item.notes.contains(Recurrence.spawnedMarker))
        #expect(!next.notes.contains(Recurrence.spawnedMarker))

        store.reopen(item)
        #expect(next.isTrashed)
        #expect(!item.notes.contains(Recurrence.spawnedMarker))
    }
}
