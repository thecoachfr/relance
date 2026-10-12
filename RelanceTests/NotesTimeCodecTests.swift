import Testing
@testable import Relance

struct NotesTimeCodecTests {
    @Test func roundTrip() {
        let encoded = NotesTimeCodec.encode(minutes: 15 * 60 + 5, notes: "Apporter le dossier")
        #expect(encoded == "⏰ 15:05\nApporter le dossier")
        let decoded = NotesTimeCodec.decode(encoded)
        #expect(decoded.minutes == 905)
        #expect(decoded.notes == "Apporter le dossier")
    }

    @Test func notesWithoutTimeAreUntouched() {
        let decoded = NotesTimeCodec.decode("Juste une note")
        #expect(decoded.minutes == nil)
        #expect(decoded.notes == "Juste une note")
    }

    @Test func malformedTimeLineIsKept() {
        let decoded = NotesTimeCodec.decode("⏰ bientôt")
        #expect(decoded.minutes == nil)
        #expect(decoded.notes == "⏰ bientôt")
    }

    @Test func timeOnly() {
        #expect(NotesTimeCodec.encode(minutes: 9 * 60, notes: "") == "⏰ 09:00")
        #expect(NotesTimeCodec.decode("⏰ 09:00").minutes == 540)
    }

    @Test func timeCategoryAndNotes() {
        let encoded = NotesTimeCodec.encode(minutes: 10 * 60, category: "Administratif", notes: "Formulaire bleu")
        #expect(encoded == "⏰ 10:00\n🏷 Administratif\nFormulaire bleu")
        #expect(NotesTimeCodec.decode(encoded) == .init(minutes: 600, category: "Administratif", notes: "Formulaire bleu"))
    }

    /// Le tri du matin peut écrire 🏷 sans ⏰, et la suggestion 💡 reste dans les notes.
    @Test func categoryWithoutTimeAndSuggestion() {
        let decoded = NotesTimeCodec.decode("🏷 Santé\n💡 Suggestion : jeudi")
        #expect(decoded.minutes == nil)
        #expect(decoded.category == "Santé")
        #expect(decoded.notes == "💡 Suggestion : jeudi")
        #expect(TaskCategory(name: "santé") == .sante)
    }
}
