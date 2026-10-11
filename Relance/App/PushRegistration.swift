import Foundation
import UIKit

/// Envoie le jeton de notification push à Home Assistant (webhook), pour que la vigie
/// puisse réveiller l'app quand la liste Google Tasks change.
enum PushRegistration {
    private static let sentKey = "pushTokenSent"
    private static let sentAtKey = "pushTokenSentAt"

    static var webhookURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RelanceWebhookURL") as? String,
              raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }

    static func register(token data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        let defaults = UserDefaults.standard
        // Renvoyé si le jeton change, et au moins une fois par semaine au cas où HA l'aurait perdu.
        let lastSent = defaults.object(forKey: sentAtKey) as? Date ?? .distantPast
        guard let url = webhookURL,
              defaults.string(forKey: sentKey) != token || lastSent < .now.addingTimeInterval(-7 * 86400)
        else { return }

        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "token": token,
            "environment": environment,
            "device": UIDevice.current.name,
        ])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else { return }
        defaults.set(token, forKey: sentKey)
        defaults.set(Date.now, forKey: sentAtKey)
    }
}
