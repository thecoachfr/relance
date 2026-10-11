import GoogleSignIn
import UIKit

/// Connexion au compte Google, avec le seul accès nécessaire : Google Tasks.
@Observable
final class GoogleAuth {
    static let tasksScope = "https://www.googleapis.com/auth/tasks"

    private(set) var email: String?
    private(set) var isRestoring = true

    var isSignedIn: Bool { email != nil }

    func restore() async {
        defer { isRestoring = false }
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
        if let user, user.grantedScopes?.contains(Self.tasksScope) == true {
            email = user.profile?.email
        }
    }

    func signIn() async throws {
        guard let presenter = Self.topViewController() else { return }
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter, hint: nil, additionalScopes: [Self.tasksScope])
        // Google permet de décocher l'accès aux tâches sur son écran de consentement.
        guard result.user.grantedScopes?.contains(Self.tasksScope) == true else {
            GIDSignIn.sharedInstance.signOut()
            throw TasksAPIError.missingScope
        }
        email = result.user.profile?.email
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        email = nil
    }

    /// Jeton d'accès valide, rafraîchi si besoin.
    func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw TasksAPIError.notSignedIn }
        return try await user.refreshTokensIfNeeded().accessToken.tokenString
    }

    func handle(_ url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
