import Foundation
import SwiftData

/// Espace partagé entre l'app, les widgets et l'activité en direct.
nonisolated enum AppGroup {
    static let id = "group.fr.alexandrefau.relance"

    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    static func modelContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(groupContainer: .identifier(id))
        return try! ModelContainer(for: TaskItem.self, configurations: configuration)
    }
}

/// Ce dont le magasin a besoin du compte Google, sans dépendre du SDK (absent des widgets).
protocol AccountProvider: AnyObject, Sendable {
    var isSignedIn: Bool { get }
    func accessToken() async throws -> String
    func signOut()
    /// Pour la montre : jeton de renouvellement et identifiant client OAuth (nil si déconnecté).
    var watchCredentials: (refreshToken: String, clientID: String)? { get }
}
