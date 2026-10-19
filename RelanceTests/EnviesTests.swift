import Foundation
import Testing
@testable import Relance

/// Envies : types (voir, lire, écouter, regarder), phrase dite à Siri, liens partagés.
struct EnviesTests {
    let calendar = Calendar.current
    func day(_ d: Int, _ m: Int, _ y: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

    @Test func kindsRoundTrip() {
        for kind in ToSee.Kind.allCases {
            let envie = ToSee(kind, end: day(31, 1, 2027))
            let notes = ToSee.notes("Conseillé par Paul", setting: envie)
            #expect(ToSee(notes: notes) == envie)
            #expect(NoteLines.visible(notes) == "Conseillé par Paul")
        }
        #expect(ToSee(.watch).lines == ["🎬 À regarder"])
        #expect(ToSee(notes: "📖 À lire")?.kind == .read)
        #expect(ToSee(notes: "🎧\u{FE0F} À écouter")?.kind == .listen)
        // L'ancien « À voir » reste une sortie.
        #expect(ToSee(notes: "👀 À voir")?.kind == .outing)
        // Changer de type remplace la ligne, sans en laisser deux.
        let changed = ToSee.notes(ToSee.notes("", setting: ToSee(.outing)), setting: ToSee(.watch))
        #expect(changed == "🎬 À regarder")
        #expect(ToSee.Kind.read.title == "À lire")
    }

    /// Restos, magasins, spots photo (P9-A2) : marqueurs lus par la routine et le Nest Hub, note du spot.
    @Test func placeKindsAndNote() {
        #expect(ToSee(.restaurant).lines == ["🍽 À tester"])
        #expect(ToSee(notes: "🛍\u{FE0F} Magasin")?.kind == .shop)
        let spot = ToSee(.photoSpot, note: "au couchant, en automne")
        let notes = ToSee.notes("📍 Pont Marie · https://maps.apple.com/?ll=48.8519,2.3572", setting: spot)
        #expect(notes.hasSuffix("\n📷 Spot photo · au couchant, en automne"))
        #expect(ToSee(notes: notes) == spot)
        #expect(NoteLines.visible(notes).isEmpty)
        // Note vide ou multiligne : pas de « · » seul, une seule ligne.
        #expect(ToSee(.photoSpot, note: "").lines == ["📷 Spot photo"])
        #expect(ToSee(.photoSpot, note: "brume\nmatin").lines == ["📷 Spot photo · brume matin"])
        #expect(ToSee(notes: "📷 Spot photo ·  ")?.note == nil)
        #expect(ToSee.Kind.allCases.filter(\.isPlace) == [.outing, .event, .restaurant, .shop, .photoSpot])
        #expect(ToSee.Kind.restaurant.doneTitle == "Testé" && ToSee.Kind.photoSpot.doneTitle == "Photographié")
        #expect(ToSee.kind(in: "le resto italien de la rue de Lyon à tester")?.kind == .restaurant)
    }

    @Test func kindInAPhrase() {
        let text = "Perfect Days à regarder"
        let found = ToSee.kind(in: text)
        #expect(found?.kind == .watch)
        #expect(found.map { String(text[..<$0.range.lowerBound]) } == "Perfect Days")
        #expect(ToSee.kind(in: "à lire : L'Anomalie")?.kind == .read)
        #expect(ToSee.kind(in: "le dernier album de Feist, à écouter")?.kind == .listen)
        #expect(ToSee.kind(in: "l'expo Penn à voir.")?.kind == .outing)
        // « voir » ailleurs dans la phrase n'est pas une envie.
        #expect(ToSee.kind(in: "voir le comptable vendredi") == nil)
        #expect(ToSee.kind(in: "aller voir mamie") == nil)
        #expect(ToSee.kind(in: "à lire") == nil)
    }

    @Test func siriKeepsAnEnvieWithoutAskingWhen() {
        #expect(!SiriCapture.needsWhen("Dune à regarder"))
        let r = SiriCapture.parse(text: "dune à regarder", when: nil)
        #expect(r == SiriCapture.Result(title: "Dune", kind: .watch))
        #expect(SiriCapture.confirmation(r) == "C'est noté : Dune, à regarder. Elle t'attend dans Envies.")
    }

    @Test func sharedLinkKinds() {
        func kind(_ s: String, linkOnly: Bool = true) -> ToSee.Kind? { SharedLink.kind(for: URL(string: s)!, linkOnly: linkOnly) }
        #expect(kind("https://www.youtube.com/watch?v=abc") == .watch)
        #expect(kind("https://youtu.be/abc") == .watch)
        #expect(kind("https://music.youtube.com/watch?v=abc") == .listen)
        #expect(kind("https://open.spotify.com/album/123") == .listen)
        #expect(kind("https://music.apple.com/fr/album/x/1") == .listen)
        #expect(kind("https://www.senscritique.com/livre/x/1") == .read)
        #expect(kind("https://www.senscritique.com/film/x/1") == .watch)
        // Un lien seul vers un autre site : un article.
        #expect(kind("https://www.example.com/2026/10/un-article") == .read)
        #expect(kind("https://www.example.com/") == nil)
        // Un message qui contient un lien quelconque reste une tâche.
        #expect(kind("https://www.example.com/devis.pdf", linkOnly: false) == nil)
    }

    @Test func pageTitle() {
        #expect(SharedLink.title(inHTML: #"<head><meta property="og:title" content="Perfect Days &amp; co"><title>x - YouTube</title>"#) == "Perfect Days & co")
        #expect(SharedLink.title(inHTML: "<html><title>Perfect Days - YouTube</title></html>") == "Perfect Days")
        #expect(SharedLink.title(inHTML: "<html></html>") == nil)
        #expect(ToSee.link(in: "📩 Message partagé\nRegarde ça https://youtu.be/abc !") == URL(string: "https://youtu.be/abc"))
    }

    @Test func groupsByKind() {
        let film = TaskItem(title: "Dune", notes: ToSee(.watch).lines.joined(separator: "\n"))
        let book = TaskItem(title: "L'Anomalie", notes: ToSee(.read).lines.joined(separator: "\n"))
        let expo = TaskItem(title: "Expo", notes: ToSee(end: day(31, 1, 2027)).lines.joined(separator: "\n"))
        let task = TaskItem(title: "Garage", dueDay: day(20, 10, 2026))
        let all = ToSeeListView.groups([film, book, expo, task], now: day(15, 10, 2026))
        #expect(all.map(\.title) == ["À voir", "À lire", "À regarder"])
        let read = ToSeeListView.groups([film, book, expo], kind: .read, now: day(15, 10, 2026))
        #expect(read.map(\.title) == ["Quand tu veux"])
        #expect(read.first?.items.map(\.title) == ["L'Anomalie"])
        #expect(!film.needsTriage)
    }
}
