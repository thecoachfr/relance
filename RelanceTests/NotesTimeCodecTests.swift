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

    /// Emojis écrits avec le sélecteur de variante U+FE0F (« ⏰️ », « 🏷️ »).
    @Test func markersWithVariationSelector() {
        let decoded = NotesTimeCodec.decode("⏰\u{FE0F} 15:00\n🏷\u{FE0F} Maison\nNotes")
        #expect(decoded == .init(minutes: 900, category: "Maison", notes: "Notes"))
    }
}

struct ReminderOverrideTests {
    @Test func lineRoundTrip() {
        let r = ReminderOverride(advance: .minutes(24 * 60), followUp: .every(15))
        #expect(r.line == "🔁 Prévenir 1 jour avant · Relancer toutes les 15 min")
        #expect(ReminderOverride(line: r.line!) == r)
        #expect(ReminderOverride(line: "🔁 Ne pas relancer") == ReminderOverride(followUp: .off))
        #expect(ReminderOverride(line: "🔁 Relancer après 2 h")?.followUp == .once(120))
        #expect(ReminderOverride(line: "🔁 n'importe quoi") == nil)
    }

    /// La ligne se range après la priorité ; une ligne illisible reste dans les notes, intacte.
    @Test func notesWithOverride() {
        let r = ReminderOverride(advance: .minutes(15))
        let encoded = NotesTimeCodec.encode(minutes: 600, priority: .urgent, reminders: r, notes: "x")
        #expect(encoded == "⏰ 10:00\n❗ Urgente\n🔁 Prévenir 15 min avant\nx")
        #expect(NotesTimeCodec.decode(encoded).reminders == r)
        #expect(NotesTimeCodec.decode("🔁 bla\nx").notes == "🔁 bla\nx")
    }

    @Test func overrideReplacesProfile() {
        let p = ReminderOverride(followUp: .every(15)).applied(to: .defaults(for: .normal))
        #expect(p.followUpMinutes == 15 && p.followUpRepeats)
        #expect(ReminderOverride(followUp: .off).applied(to: .defaults(for: .urgent)).followUpMinutes == nil)
    }
}
