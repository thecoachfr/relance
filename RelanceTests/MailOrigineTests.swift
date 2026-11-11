import Foundation
import Testing
@testable import Relance

/// « Voir le mail » (11/11) : lien Gmail des notes d'une tâche venue d'un mail, caché dans le champ Notes.
struct MailOrigineTests {
    let notes = "https://mail.google.com/mail/u/0/#inbox/19a2b3c4d5e6f708\nRDV confirmé chez le Dr Martin.\n📧 Mail de Doctolib\n📌 Rendez-vous"

    @Test func lienEtFil() {
        #expect(MailOrigine.lien(in: notes)?.absoluteString == "https://mail.google.com/mail/u/0/#inbox/19a2b3c4d5e6f708")
        #expect(MailOrigine.fil(in: notes) == "19a2b3c4d5e6f708")
        #expect(MailOrigine.destination(in: notes) == MailOrigine.lien(in: notes))
        #expect(MailOrigine.dansCourrier(in: notes)?.absoluteString == "courrier://fil/19a2b3c4d5e6f708")
    }

    @Test func sansMail() {
        #expect(MailOrigine.lien(in: "Appeler le garage\nhttps://example.com/mail.google.com") == nil)
        #expect(MailOrigine.lien(in: "") == nil)
        #expect(MailOrigine.dansCourrier(in: "") == nil)
        #expect(MailOrigine.fil(in: "https://mail.google.com/mail/u/0/#inbox/../x;y") == nil)
    }

    @Test func ligneCacheeMaisGardee() {
        #expect(NoteLines.visible(notes) == "RDV confirmé chez le Dr Martin.\n📧 Mail de Doctolib")
        // Modifier le texte visible garde le lien dans les données (lu par la vigie et l'app Courrier).
        let modifiees = NoteLines.replacingVisible(in: notes, with: "Apporter l'ordonnance")
        #expect(modifiees.contains("https://mail.google.com/mail/u/0/#inbox/19a2b3c4d5e6f708"))
        #expect(MailOrigine.fil(in: modifiees) == "19a2b3c4d5e6f708")
        #expect(NoteLines.visible(modifiees) == "Apporter l'ordonnance")
        // Un autre lien reste visible (et ouvrable par Actions › « Ouvrir le lien »).
        #expect(NoteLines.visible("https://www.doctolib.fr/rdv") == "https://www.doctolib.fr/rdv")
    }
}
