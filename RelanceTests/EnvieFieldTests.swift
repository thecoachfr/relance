import Foundation
import Testing
@testable import Relance

/// Champ `envie` des tâches dans Home Assistant (P9-B1), copie des lignes de type des notes.
struct EnvieFieldTests {
    private func decode(_ json: String) throws -> TacheHA {
        try JSONDecoder().decode(TacheHA.self, from: Data(json.utf8))
    }

    /// Ancienne tâche (lignes seules) : l'envie est déduite, avec le lien et sa plateforme.
    @Test func derivedFromLines() throws {
        let item = TaskItem(title: "Regarder la vidéo", notes: "📩 Message partagé\nhttps://youtube.com/watch?v=JPcVyq_BYjU\n🎬 À regarder")
        let envie = try #require(TacheHA(item).envie)
        #expect(envie.type == "regarder" && envie.plateforme == "youtube" && envie.lien == "https://youtube.com/watch?v=JPcVyq_BYjU")
        let json = String(decoding: try JSONEncoder().encode(TacheHA(item)), as: UTF8.self)
        #expect(json.contains(#""v":2"#) && json.contains(#""envie":{"#))
        // Pas d'envie, pas de champ.
        #expect(TacheHA(TaskItem(title: "Pain")).envie == nil)
    }

    /// Les champs de la vigie (TMDB, disponibilités) et l'identifiant survivent à une réécriture par l'app.
    @Test func vigieFieldsAreKept() throws {
        let item = TaskItem(title: "")
        try decode(#"""
        {"titre":"The Bear","notes":"🎬 À regarder","envie":{"type":"regarder","plateforme":"disney","id_titre":"abc",
         "tmdb":{"id":136315,"type":"tv"},"dispo_fr":{"abonnement":["disney"]},"dispo_maj":"2026-10-16"}}
        """#).apply(to: item)
        item.title = "The Bear (saison 4)"
        let envie = try #require(TacheHA(item).envie)
        #expect(envie.plateforme == "disney" && envie.idTitre == "abc")
        #expect(envie.autres["dispo_maj"] == "2026-10-16" && envie.autres["tmdb"] != nil)
        let json = String(decoding: try JSONEncoder().encode(TacheHA(item)), as: UTF8.self)
        #expect(json.contains(#""id_titre":"abc""#) && json.contains(#""tmdb""#) && json.contains(#""dispo_fr""#))
    }

    /// Type changé dans l'app : la plateforme et les champs liés au titre ne suivent pas.
    @Test func typeChangeDropsTitleFields() throws {
        let item = TaskItem(title: "")
        try decode(#"{"titre":"Dune","notes":"🎬 À regarder","envie":{"type":"regarder","plateforme":"netflix","tmdb":{"id":1}}}"#)
            .apply(to: item)
        item.notes = ToSee.notes(item.notes, setting: ToSee(.read))
        let envie = try #require(TacheHA(item).envie)
        #expect(envie.type == "lire" && envie.plateforme == nil && envie.autres.isEmpty)
    }

    /// L'envie fait foi : type et note réécrits sur la ligne, période gardée.
    @Test func fieldWinsOverLinesAndKeepsPeriod() throws {
        let item = TaskItem(title: "")
        try decode(#"{"titre":"Pont","notes":"👀 À voir\n🗓 Jusqu'au 31/01/2027","envie":{"type":"spot_photo","note":"au couchant"}}"#)
            .apply(to: item)
        let toSee = try #require(ToSee(notes: item.notes))
        #expect(toSee.kind == .photoSpot && toSee.note == "au couchant" && toSee.end != nil)
        #expect(!item.notes.contains("👀"))
        #expect(ToSee.Kind.allCases.allSatisfy { ToSee.Kind(haType: $0.haType) == $0 })
    }

    @Test func platformsFromLinks() {
        #expect(SharedLink.platform(for: URL(string: "https://www.netflix.com/title/81234567")!) == "netflix")
        #expect(SharedLink.platform(for: URL(string: "https://tv.apple.com/fr/show/x")!) == "apple_tv")
        #expect(SharedLink.platform(for: URL(string: "https://open.spotify.com/track/6A5p")!) == "spotify")
        #expect(SharedLink.platform(for: URL(string: "https://www.lefigaro.fr/sports")!) == nil)
    }
}

/// Liens réels partagés par Alexandre le 16/10 (P9-B1).
struct RealWatchLinksTests {
    let netflix = URL(string: "https://www.netflix.com/fr/title/81674500?s=i&trkid=13747225&shareType=Title&shareUuid=4F902043-EE6D-4007-AAE7-56CAF14851F4&trg=cp&unifiedEntityIdEncoded=Video%3A81674500&vlang=fr")!
    let canal = URL(string: "https://mycan.al/series/monarch-legacy-of-monsters/h/40002718_50696")!

    @Test func netflixLink() {
        #expect(SharedLink.kind(for: netflix, linkOnly: true) == .watch)
        #expect(SharedLink.platform(for: netflix) == "netflix" && SharedLink.titleID(for: netflix) == "81674500")
        #expect(SharedLink.title(inHTML: "<title>Netflix</title>") == nil)
    }

    @Test func canalLink() {
        #expect(SharedLink.kind(for: canal, linkOnly: true) == .watch)
        #expect(SharedLink.platform(for: canal) == "canal" && SharedLink.titleID(for: canal) == "40002718_50696")
        #expect(SharedLink.titleInPath(of: canal) == "Monarch legacy of monsters")
        let long = URL(string: "https://www.canalplus.com/series/monarch-legacy-of-monsters/h/40002718_50696")!
        #expect(SharedLink.titleID(for: long) == "40002718_50696")
    }

    let disney = URL(string: "https://disneyplus.com/fr-FR/browse/entity-8744ec55-8d14-4631-99b4-c889a2d6013f?sharesource=iOS")!

    @Test func disneyLink() {
        #expect(SharedLink.kind(for: disney, linkOnly: false) == .watch)
        #expect(SharedLink.platform(for: disney) == "disney")
        #expect(SharedLink.titleID(for: disney) == "8744ec55-8d14-4631-99b4-c889a2d6013f")
        // Le texte partagé par Disney+ donne le titre entre guillemets.
        let text = "\(disney.absoluteString) Je pense que tu aimeras « VisionQuest » sur Disney+."
        #expect(SharedLink.quotedTitle(in: text) == "VisionQuest")
        #expect(SharedLink.quotedTitle(in: "Rien entre guillemets") == nil)
    }

    @Test func envieGetsTheID() throws {
        let item = TaskItem(title: "Monarch", notes: "📩 Message partagé\n\(canal.absoluteString)\n🎬 À regarder")
        let envie = try #require(TacheHA(item).envie)
        #expect(envie.plateforme == "canal" && envie.idTitre == "40002718_50696")
    }
}

/// « Sur la TV » (P9-B4) : forme du lien envoyé au Player.
struct TVLinkTests {
    @Test func netflixGetsSource30() {
        let shared = URL(string: "https://www.netflix.com/fr/title/81674500?s=i&trkid=13747225&shareType=Title&vlang=fr")!
        #expect(TVRemote.link(for: shared) == "https://www.netflix.com/title/81674500?source=30")
        let disney = URL(string: "https://disneyplus.com/fr-FR/browse/entity-8744ec55-8d14-4631-99b4-c889a2d6013f?sharesource=iOS")!
        #expect(TVRemote.link(for: disney) == "https://www.disneyplus.com/fr-fr/browse/entity-8744ec55-8d14-4631-99b4-c889a2d6013f")
        let canal = URL(string: "https://mycan.al/series/monarch-legacy-of-monsters/h/40002718_50696")!
        #expect(TVRemote.link(for: canal) == canal.absoluteString)
        let youtube = URL(string: "https://youtube.com/watch?v=JPcVyq_BYjU&is=ZlKEp7FwF3XJ2x_c")!
        #expect(TVRemote.link(for: youtube) == "https://www.youtube.com/watch?v=JPcVyq_BYjU")
        #expect(TVRemote.link(for: URL(string: "https://youtu.be/JPcVyq_BYjU?si=x")!) == "https://www.youtube.com/watch?v=JPcVyq_BYjU")
        let spotify = URL(string: "https://open.spotify.com/track/6A5pZE8XuTjJbrpQ3mpeNc?si=hYKMyWtiSFqxBQUkAGemSg&utm_source=native-share-menu")!
        #expect(SharedLink.titleID(for: spotify) == "track:6A5pZE8XuTjJbrpQ3mpeNc")
        #expect(TVRemote.link(for: spotify) == "https://open.spotify.com/track/6A5pZE8XuTjJbrpQ3mpeNc")
    }
}

/// Disponibilités écrites par la vigie (P9-B3), relues par l'app.
struct AvailabilityTests {
    @Test func readsWhatTheVigieWrites() throws {
        let item = TaskItem(title: "")
        try JSONDecoder().decode(TacheHA.self, from: Data(#"""
        {"titre":"The Bear","notes":"🎬 À regarder","envie":{"type":"regarder","plateforme":"disney",
         "tmdb":{"id":136315,"type":"tv","titre":"The Bear","annee":2022,"affiche":"https://image.tmdb.org/t/p/w342/a.jpg"},
         "dispo_fr":{"abonnement":[{"id":337,"nom":"Disney Plus","code":"disney"}],"location":[{"id":2,"nom":"Apple TV","code":"apple_tv"}]},
         "dispo_maj":"2026-10-16"}}
        """#.utf8)).apply(to: item)
        let a = try #require(item.availability)
        #expect(a.title == "The Bear" && a.year == 2022 && a.poster?.lastPathComponent == "a.jpg")
        #expect(a.subscription == [.init(name: "Disney Plus", code: "disney")] && a.rent.first?.code == "apple_tv")
        #expect(a.buy.isEmpty && a.checked == "2026-10-16" && a.status == nil)
    }

    @Test func ambiguousAndAbsent() throws {
        let item = TaskItem(title: "")
        try JSONDecoder().decode(TacheHA.self, from: Data(#"{"titre":"Dune","envie":{"type":"regarder","tmdb_statut":"ambigu","tmdb_maj":"2026-10-16"}}"#.utf8))
            .apply(to: item)
        #expect(item.availability?.status == "ambigu")
        #expect(TaskItem(title: "x").availability == nil)
    }
}
