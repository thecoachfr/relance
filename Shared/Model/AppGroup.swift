import Foundation
import SwiftData

/// Espace partagé entre l'app, les widgets et l'activité en direct.
nonisolated enum AppGroup {
    static let id = "group.fr.alexandrefau.relance"

    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    static func modelContainer(inMemory: Bool = false) -> ModelContainer {
        // Sans `cloudKitDatabase: .none`, SwiftData active seul la synchro CloudKit dès que l'app a la
        // capacité iCloud (fallback de DonneesHA), et refuse alors le modèle : plantage au lancement.
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(groupContainer: .identifier(id), cloudKitDatabase: .none)
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
