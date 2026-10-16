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
        ("canalplus.com", .watch), ("mycan.al", .watch), ("france.tv", .watch), ("arte.tv", .watch), ("max.com", .watch),
        ("twitch.tv", .watch), ("imdb.com", .watch), ("allocine.fr", .watch), ("letterboxd.com", .watch),
        ("books.apple.com", .read), ("goodreads.com", .read), ("babelio.com", .read), ("medium.com", .read),
        ("substack.com", .read),
    ]

    /// Plateforme d'après l'adresse (champ `envie.plateforme`, P9-B1). Seulement les hôtes connus ;
    /// l'identifiant du titre attend de vrais liens partagés (formats à vérifier).
    private static let platforms: [(String, String)] = [
        ("music.youtube.com", "youtube_music"), ("music.apple.com", "apple_music"), ("podcasts.apple.com", "apple_podcasts"),
        ("open.spotify.com", "spotify"), ("spotify.link", "spotify"), ("deezer.com", "deezer"), ("deezer.page.link", "deezer"),
        ("youtube.com", "youtube"), ("youtu.be", "youtube"), ("netflix.com", "netflix"), ("primevideo.com", "prime"),
        ("disneyplus.com", "disney"), ("tv.apple.com", "apple_tv"), ("canalplus.com", "canal"), ("mycan.al", "canal"),
        ("france.tv", "france_tv"),
        ("arte.tv", "arte"), ("max.com", "max"), ("twitch.tv", "twitch"), ("vimeo.com", "vimeo"),
    ]

    static func platform(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        return platforms.first { host == $0.0 || host.hasSuffix("." + $0.0) }?.1
    }

    /// Nom affiché d'une plateforme.
    static func platformName(_ platform: String) -> String {
        ["netflix": "Netflix", "disney": "Disney+", "apple_tv": "Apple TV", "canal": "Canal+", "prime": "Prime Video",
         "youtube": "YouTube", "france_tv": "france.tv", "arte": "Arte", "max": "Max", "spotify": "Spotify",
         "deezer": "Deezer", "apple_music": "Apple Music", "youtube_music": "YouTube Music"][platform] ?? platform
    }

    /// Identifiant du titre dans le lien (champ `envie.id_titre`). Formats vus sur de vrais partages le 16/10 :
    /// Netflix `netflix.com/fr/title/81674500?s=i&trkid=…` ; Canal+ `mycan.al/series/<titre>/h/40002718_50696`
    /// (→ `canalplus.com/…` même chemin). Les autres plateformes attendent leurs liens réels.
    static func titleID(for url: URL) -> String? {
        let path = url.path()
        switch platform(for: url) {
        case "netflix": return path.firstMatch(of: /\/title\/(\d+)/).map { String($0.1) }
        case "canal": return path.firstMatch(of: /\/h\/([0-9_]+)/).map { String($0.1) }
        // YouTube : `youtube.com/watch?v=<id>&is=…`, `youtu.be/<id>`, `youtube.com/shorts/<id>`.
        case "youtube":
            if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
                return v
            }
            let parts = path.split(separator: "/").map(String.init)
            if url.host()?.lowercased() == "youtu.be" { return parts.first }
            return parts.count == 2 && ["shorts", "live", "embed"].contains(parts[0]) ? parts[1] : nil
        // Spotify : `open.spotify.com/track/<id>?si=…` (aussi album, playlist, episode).
        case "spotify":
            let parts = path.split(separator: "/").map(String.init).filter { !$0.hasPrefix("intl-") }
            return parts.count >= 2 && ["track", "album", "playlist", "episode", "show", "artist"].contains(parts[0])
                ? parts[0] + ":" + parts[1] : nil
        // Disney+ : `disneyplus.com/fr-FR/browse/entity-8744ec55-…?sharesource=iOS`.
        case "disney": return path.firstMatch(of: /entity-([0-9a-fA-F-]{36})/).map { String($0.1).lowercased() }
        default: return nil
        }
    }

    /// Titre entre guillemets dans le texte partagé (Disney+ : « Je pense que tu aimeras « VisionQuest » sur
    /// Disney+. »).
    static func quotedTitle(in text: String) -> String? {
        text.firstMatch(of: /«\s*([^»]{1,120}?)\s*»/).map { String($0.1) }
    }

    /// Titre lisible dans l'adresse quand la page ne le donne pas (Canal+ refuse les robots, 403) :
    /// `…/series/monarch-legacy-of-monsters/h/…` → « Monarch legacy of monsters ».
    static func titleInPath(of url: URL) -> String? {
        guard platform(for: url) == "canal" else { return nil }
        let parts = url.path().split(separator: "/").map(String.init)
        guard let h = parts.firstIndex(of: "h"), h >= 1 else { return nil }
        let slug = parts[h - 1].replacingOccurrences(of: "-", with: " ")
        guard !slug.isEmpty, !["series", "films", "cinema"].contains(slug) else { return nil }
        return slug.prefix(1).uppercased() + slug.dropFirst()
    }

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
            // Page d'erreur ou nom du site seul : pas un titre (le lien Google Maps a donné le premier, le 16/10).
            let generic = ["dynamic link not found", "google maps", "apple maps", "plans", "page not found", "404",
                           "netflix", "canal+", "mycanal", "disney+", "prime video", "apple tv"]
            if !title.isEmpty, !generic.contains(title.lowercased()) { return title }
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
