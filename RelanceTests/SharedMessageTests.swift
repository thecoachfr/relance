import Foundation
import Testing
@testable import Relance

struct SharedMessageTests {
    let calendar = Calendar.current

    /// Un message seul : on saute la salutation, la date dite devient l'échéance.
    @Test func singleMessage() {
        let d = SharedMessage.draft(from: "Salut ! Tu peux me renvoyer le devis signé demain à 15h ? Merci")
        #expect(d.title == "Tu peux me renvoyer le devis signé")
        #expect(d.minutes == 15 * 60)
        #expect(d.day == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)))
        #expect(d.priority == .normal)
    }

    /// Plusieurs messages : les en-têtes « [date] Nom : » sont retirés (leur date ne doit pas devenir l'échéance).
    @Test func whatsAppHeaders() {
        let text = """
        [12/10/2026 14:03:15] Paul : Bonjour Alex,
        [12/10/2026 14:03:40] Paul : il faut appeler l'assurance pour le sinistre, c'est urgent
        """
        let d = SharedMessage.draft(from: text)
        #expect(d.body == "Bonjour Alex,\nil faut appeler l'assurance pour le sinistre, c'est urgent")
        #expect(d.title == "Il faut appeler l'assurance pour le sinistre")
        #expect(d.priority == .urgent)
        #expect(d.day == nil)
        #expect(SharedMessage.body(of: "12/10/2026 14:03 - Paul: ok") == "ok")
    }

    @Test func longTitleIsCutOnAWord() {
        let d = SharedMessage.draft(from: String(repeating: "relancer le fournisseur de bois ", count: 4))
        #expect(d.title.count <= SharedMessage.maxTitleLength + 1)
        #expect(d.title.hasSuffix("…"))
        #expect(!d.title.contains("  "))
    }

    @Test func linkOnly() {
        #expect(SharedMessage.draft(from: "https://www.service-public.fr/particuliers/vosdroits/F1234").title == "Lire service-public.fr")
    }

    /// Le tri ne propose un titre que si l'utilisateur ne l'a pas retouché.
    @Test func notesMarker() {
        #expect(SharedMessage.notes(original: " msg ", titleEdited: false) == "📩 Message partagé — titre à revoir\nmsg")
        #expect(SharedMessage.notes(original: "msg", titleEdited: true) == "📩 Message partagé\nmsg")
    }

    /// Message réel du 12/10 : la formule de politesse ne doit pas devenir le titre.
    @Test func pleasantriesAreSkipped() {
        let d = SharedMessage.draft(from: "Coucou alex. J’espère que tout va bien.  Bloque ton 16 dec. Je vais faire un pot de départ dans un bar avec les anciens. Bisous")
        #expect(!d.title.localizedCaseInsensitiveContains("espère"))
        #expect(d.title.hasPrefix("Bloque ton"))
        #expect(SharedMessage.draft(from: "Merci ! Peux-tu rappeler le plombier").title == "Peux-tu rappeler le plombier")
    }
}

struct TaskContactTests {
    @Test func contactLine() {
        let notes = "Apporter la radio\n📍 Dr Claire Martin · 12 rue de la Paix, 75002 Paris · 01 43 75 00 00 · https://www.doctolib.fr/x"
        let c = TaskContact(notes: notes)
        #expect(c?.name == "Dr Claire Martin")
        #expect(c?.address == "12 rue de la Paix, 75002 Paris")
        #expect(c?.phoneURL?.absoluteString == "tel:0143750000")
        #expect(c?.link?.host() == "www.doctolib.fr")
        #expect(c?.mapsURL?.absoluteString.contains("daddr=12") == true)
        #expect(TaskContact(notes: "📍 Cabinet Dupont")?.address == nil)
        #expect(TaskContact(notes: "rien") == nil)
        #expect(c?.isBookingLink == true)
        #expect(TaskContact(name: "Mairie", link: URL(string: "https://www.paris.fr")).isBookingLink == false)
    }

    /// Lieu choisi à la main : remplace la ligne existante à sa place, s'ajoute à la fin, ou se retire.
    @Test func settingPlace() {
        let place = TaskContact(name: "Pharmacie du Centre", address: "3 place de la Mairie, 75002 Paris",
                                phone: "01 40 00 00 00", link: URL(string: "https://example.fr"))
        #expect(place.line == "📍 Pharmacie du Centre · 3 place de la Mairie, 75002 Paris · 01 40 00 00 00 · https://example.fr")
        #expect(TaskContact(notes: place.line) == place)
        #expect(TaskContact.notes("Apporter l'ordonnance\n", setting: place) == "Apporter l'ordonnance\n" + place.line)
        #expect(TaskContact.notes("", setting: place) == place.line)
        let replaced = TaskContact.notes("a\n📍 Ancien lieu\nb", setting: TaskContact(name: "Mairie"))
        #expect(replaced == "a\n📍 Mairie\nb")
        #expect(TaskContact.notes("a\n📍 Ancien lieu\nb", setting: nil) == "a\nb")
    }
}

struct NoteLinesTests {
    @Test func hidesTechnicalLinesAndKeepsThem() {
        let notes = "📩 Message partagé\nCoucou, bloque ton 16.\n📍 Mairie · 1 place de la Mairie\n🎒 À prendre : carte\n📅 Dans l'agenda"
        #expect(NoteLines.visible(notes) == "Coucou, bloque ton 16.\n🎒 À prendre : carte")
        // Rien de changé : notes identiques.
        #expect(NoteLines.replacingVisible(in: notes, with: NoteLines.visible(notes)) == notes)
        // Texte modifié : les lignes cachées sont gardées, à la fin.
        let edited = NoteLines.replacingVisible(in: notes, with: "Pot de départ")
        #expect(edited == "Pot de départ\n📩 Message partagé\n📍 Mairie · 1 place de la Mairie\n📅 Dans l'agenda")
        #expect(TaskContact(notes: edited)?.name == "Mairie")
        #expect(NoteLines.replacingVisible(in: "📍 Mairie", with: "") == "📍 Mairie")
        #expect(NoteLines.visible("📍\u{FE0F} Mairie\nx") == "x")
    }
}
