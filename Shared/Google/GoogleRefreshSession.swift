import Foundation
import os
import Security

/// Connexion Google sans le SDK : jeton de renouvellement gardé dans le trousseau,
/// jeton d'accès demandé à Google directement.
/// - Montre : reçoit la connexion de l'iPhone (fonctionne en 4G, iPhone absent).
/// - Extension de partage : lit la connexion que l'app range dans le trousseau partagé (`shared`).
final class GoogleRefreshSession: @unchecked Sendable {
    private static let service = "fr.alexandrefau.relance.google"
    /// Groupe de trousseau commun à l'app iPhone et à son extension de partage.
    static let sharedAccessGroup = "GD6W292ZXP.fr.alexandrefau.relance.shared"
    static var shared: GoogleRefreshSession { GoogleRefreshSession(accessGroup: sharedAccessGroup) }

    private let accessGroup: String?
    /// Jeton d'accès et renouvellement en cours, sous verrou : deux synchros simultanées ne renouvellent qu'une fois
    /// (avant : état modifiable partagé sans verrou, deux renouvellements possibles en même temps).
    private struct Etat {
        var accessToken: String?
        var expiresAt = Date.distantPast
        var renouvellement: Task<String, any Error>?
    }
    private let etat = OSAllocatedUnfairLock(initialState: Etat())

    init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    var isAvailable: Bool { credentials != nil }

    /// Enregistre ce que l'iPhone envoie ; chaînes vides = l'utilisateur s'est déconnecté.
    func store(refreshToken: String, clientID: String) {
        guard !refreshToken.isEmpty, !clientID.isEmpty else {
            delete()
            oublierJeton()
            return
        }
        guard credentials?.refreshToken != refreshToken || credentials?.clientID != clientID else { return }
        save("\(clientID)\n\(refreshToken)")
        oublierJeton()
    }

    private func oublierJeton() {
        etat.withLock { $0.accessToken = nil; $0.expiresAt = .distantPast }
    }

    func validAccessToken() async throws -> String {
        let tache: Task<String, any Error> = etat.withLock { e in
            if let jeton = e.accessToken, e.expiresAt > .now.addingTimeInterval(60) {
                return Task { jeton }
            }
            if let enCours = e.renouvellement { return enCours }
            let nouvelle = Task { try await self.renouveler() }
            e.renouvellement = nouvelle
            return nouvelle
        }
        return try await tache.value
    }

    /// Demande un jeton d'accès à Google ; un seul à la fois (`validAccessToken`).
    private func renouveler() async throws -> String {
        defer { etat.withLock { $0.renouvellement = nil } }
        guard let credentials else { throw TasksAPIError.notSignedIn }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "refresh_token", value: credentials.refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await Reseau.envoyer(request, rejouable: true)
        let status = response?.statusCode ?? 0
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            // 400 invalid_grant : accès révoqué ou déconnexion sur l'iPhone.
            if status == 400 { delete() }
            throw TasksAPIError.http(status, String(decoding: data, as: UTF8.self))
        }
        let expiration = Date.now.addingTimeInterval(TimeInterval(json["expires_in"] as? Int ?? 3600))
        etat.withLock { $0.accessToken = token; $0.expiresAt = expiration }
        return token
    }

    // MARK: - Trousseau

    private var credentials: (clientID: String, refreshToken: String)? {
        guard let raw = load() else { return nil }
        let parts = raw.split(separator: "\n", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    private func save(_ value: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let statut = SecItemAdd(item as CFDictionary, nil)
        if statut != errSecSuccess { Journal.echec(.stockage, "Trousseau : jeton Google non enregistré (OSStatus \(statut))") }
    }

    private func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
