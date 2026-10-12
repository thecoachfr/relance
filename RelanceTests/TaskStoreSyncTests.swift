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
