import Foundation
import Security

/// Connexion Google de la montre, reçue de l'iPhone : jeton de renouvellement gardé dans le trousseau,
/// jeton d'accès demandé à Google directement (fonctionne en 4G, iPhone absent).
final class WatchGoogle {
    private static let service = "fr.alexandrefau.relance.google"
    private var accessToken: String?
    private var expiresAt = Date.distantPast

    var isAvailable: Bool { credentials != nil }

    /// Enregistre ce que l'iPhone envoie ; chaînes vides = l'utilisateur s'est déconnecté.
    func store(refreshToken: String, clientID: String) {
        guard !refreshToken.isEmpty, !clientID.isEmpty else {
            Self.delete()
            accessToken = nil
            return
        }
        guard credentials?.refreshToken != refreshToken || credentials?.clientID != clientID else { return }
        Self.save("\(clientID)\n\(refreshToken)")
        accessToken = nil
    }

    func validAccessToken() async throws -> String {
        if let accessToken, expiresAt > .now.addingTimeInterval(60) { return accessToken }
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

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            // 400 invalid_grant : accès révoqué ou déconnexion sur l'iPhone.
            if status == 400 { Self.delete() }
            throw TasksAPIError.http(status, String(decoding: data, as: UTF8.self))
        }
        accessToken = token
        expiresAt = .now.addingTimeInterval(TimeInterval(json["expires_in"] as? Int ?? 3600))
        return token
    }

    // MARK: - Trousseau

    private var credentials: (clientID: String, refreshToken: String)? {
        guard let raw = Self.load() else { return nil }
        let parts = raw.split(separator: "\n", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    private static func save(_ value: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
