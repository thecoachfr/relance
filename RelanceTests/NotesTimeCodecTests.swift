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
}
