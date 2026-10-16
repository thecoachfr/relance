import Foundation

/// « Sur la TV » (plan P9-B4) : demande à Home Assistant d'ouvrir un lien sur le Freebox Player Pop, par le
/// script `script.aiguillage_sur_tv` (même adresse et même jeton que la synchro des tâches).
nonisolated enum TVRemote {
    enum Outcome: Equatable, Sendable {
        case sent
        /// Le Player ne répond pas (la nuit, il est en veille profonde).
        case unreachable
        case failed(String)
    }

    /// La forme du lien que le Player sait ouvrir, selon la plateforme (`docs/LIENS-TV.md`, essais B5 du 16/10) :
    /// Netflix `…/title/<id>?source=30` (titre, après le choix du profil) ; Disney+ seulement avec `www.` et la
    /// langue en minuscules (le lien partagé `disneyplus.com/fr-FR/…` donne « Aucune application ne peut
    /// effectuer cette action ») ; Canal+ tel quel ; YouTube `www.youtube.com/watch?v=<id>` (vidéo) ; Spotify
    /// `open.spotify.com/<type>/<id>` (affiché, pas lu) ; les autres tel quel.
    static func link(for url: URL) -> String {
        switch (SharedLink.platform(for: url), SharedLink.titleID(for: url)) {
        case ("netflix", let id?): "https://www.netflix.com/title/\(id)?source=30"
        case ("disney", let id?): "https://www.disneyplus.com/fr-fr/browse/entity-\(id)"
        // YouTube : la vidéo s'ouvre ; Spotify : le contenu s'affiche, sans lecture (essais du 16/10).
        case ("youtube", let id?): "https://www.youtube.com/watch?v=\(id)"
        case ("spotify", let id?): "https://open.spotify.com/" + id.replacingOccurrences(of: ":", with: "/")
        default: url.absoluteString
        }
    }

    static func send(_ url: URL) async -> Outcome {
        guard let base = HAConfig.url, let token = HAConfig.token, !token.isEmpty else {
            return .failed("Home Assistant n'est pas réglé (Réglages › Home Assistant).")
        }
        // La nuit, le Player est injoignable : on le dit tout de suite plutôt qu'après une erreur du script.
        var state = URLRequest(url: base.appending(path: "api/states/remote.freebox_player_pop"), timeoutInterval: 10)
        state.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: state),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["state"] as? String == "unavailable" {
            return .unreachable
        }
        var request = URLRequest(url: base.appending(path: "api/services/script/aiguillage_sur_tv"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["lien": link(for: url)])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return .sent }
            let text = String(decoding: data, as: UTF8.self)
            if text.localizedCaseInsensitiveContains("injoignable") { return .unreachable }
            return .failed("Home Assistant a répondu \(status).")
        } catch {
            return .failed("Home Assistant ne répond pas.")
        }
    }
}
