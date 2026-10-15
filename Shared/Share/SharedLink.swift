import Foundation

/// Lien partagé depuis une autre app : quelle envie (YouTube → À regarder, Spotify → À écouter…)
/// et le titre de la page, pour ne pas garder « Lire youtube.com ».
nonisolated enum SharedLink {
    /// Hôtes connus, du plus précis au plus large (`music.youtube.com` avant `youtube.com`).
    private static let hosts: [(String, ToSee.Kind)] = [
        ("music.youtube.com", .listen), ("music.apple.com", .listen), ("podcasts.apple.com", .listen),
        ("open.spotify.com", .listen), ("spotify.link", .listen), ("deezer.com", .listen), ("deezer.page.link", .listen),
        ("soundcloud.com", .listen), ("bandcamp.com", .listen), ("radiofrance.fr", .listen), ("tidal.com", .listen),
        ("qobuz.com", .listen),
        ("youtube.com", .watch), ("youtu.be", .watch), ("vimeo.com", .watch), ("dailymotion.com", .watch),
        ("netflix.com", .watch), ("primevideo.com", .watch), ("disneyplus.com", .watch), ("tv.apple.com", .watch),
        ("canalplus.com", .watch), ("france.tv", .watch), ("arte.tv", .watch), ("max.com", .watch),
        ("twitch.tv", .watch), ("imdb.com", .watch), ("allocine.fr", .watch), ("letterboxd.com", .watch),
        ("books.apple.com", .read), ("goodreads.com", .read), ("babelio.com", .read), ("medium.com", .read),
        ("substack.com", .read),
    ]

    /// Premier lien web du texte partagé.
    static func url(in text: String) -> URL? { ToSee.link(in: text) }

    /// Le type d'envie d'après l'adresse ; `.read` pour un lien seul d'un autre site (un article, le plus souvent).
    static func kind(for url: URL, linkOnly: Bool) -> ToSee.Kind? {
        guard let host = url.host()?.lowercased() else { return nil }
        if let found = hosts.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) }) { return found.1 }
        if host.hasSuffix("senscritique.com") {
            let path = url.path().lowercased()
            if path.hasPrefix("/livre") || path.hasPrefix("/bd") { return .read }
            if path.hasPrefix("/album") || path.hasPrefix("/morceau") { return .listen }
            return .watch
        }
        return linkOnly && url.path().count > 1 ? .read : nil
    }

    /// Titre de la page (`og:title`, sinon `<title>`), sans le nom du site (« … - YouTube »). `nil` après 4 s.
    static func title(of url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 4)
        // Sans navigateur reconnu, certains sites renvoient une page de consentement sans titre.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data.prefix(400_000), encoding: .utf8) ?? String(data: data.prefix(400_000), encoding: .isoLatin1)
        else { return nil }
        return title(inHTML: html)
    }

    static func title(inHTML html: String) -> String? {
        let patterns = [
            #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#,
            #"<title[^>]*>([^<]+)</title>"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(m.range(at: 1), in: html) else { continue }
            let title = cleaned(decoded(String(html[range])))
            if !title.isEmpty { return title }
        }
        return nil
    }

    /// « Perfect Days - Bande-annonce - YouTube » → « Perfect Days - Bande-annonce ».
    private static func cleaned(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - YouTube", " | Netflix", " – Apple Music", " - Apple Music", " | Spotify", " | Deezer", " | Le Monde",
                       " sur Apple Music", " - Apple Podcasts", " sur Apple Podcasts"] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count))
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func decoded(_ text: String) -> String {
        var t = text
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"),
                               ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&rsquo;", "’"), ("&eacute;", "é"),
                               ("&egrave;", "è"), ("&agrave;", "à"), ("&ccedil;", "ç")] {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        return t
    }
}
