import Foundation
import Testing
@testable import Relance

struct SiriCaptureTests {
    let calendar = Calendar.current

    /// Date et heure dans la première réponse : pas de « Pour quand ? ».
    @Test func dateInSentence() {
        #expect(!SiriCapture.needsWhen("appeler le garage vendredi à 15 h"))
        let r = SiriCapture.parse(text: "appeler le garage vendredi à 15 h", when: nil)
        #expect(r.title == "Appeler le garage")
        #expect(r.minutes == 15 * 60)
        #expect(r.day.map { calendar.component(.weekday, from: $0) } == 6)
    }

    @Test func dateInSecondAnswer() {
        #expect(SiriCapture.needsWhen("payer la cantine"))
        let r = SiriCapture.parse(text: "payer la cantine", when: "demain à 9h30")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
        #expect(r == .init(title: "Payer la cantine", day: tomorrow, minutes: 9 * 60 + 30))
    }

    /// « sans date », « je ne sais pas » : la tâche va dans À trier.
    @Test func withoutDate() {
        for answer in ["sans date", "je ne sais pas"] {
            let r = SiriCapture.parse(text: "renouveler le passeport", when: answer)
            #expect(r == .init(title: "Renouveler le passeport"))
        }
        #expect(SiriCapture.confirmation(.init(title: "X")).contains("À trier"))
    }

    /// Le détecteur ne prend que « soir » : « ce » ne doit pas rester dans le titre.
    @Test func danglingWordsRemoved() {
        let text = "appeler maman ce soir"
        #expect(DateDetection.title(of: text, removing: DateDetection.firstMatch(in: text)) == "appeler maman")
    }
}

struct PriorityTests {
    @Test func spokenPriority() {
        let urgent = SiriCapture.parse(text: "appeler le garage urgent vendredi à 15 h", when: nil)
        #expect(urgent.title == "Appeler le garage")
        #expect(urgent.priority == .urgent)
        #expect(urgent.minutes == 15 * 60)

        // « pas pressé » / « pas urgent » ne doivent jamais être lus comme « urgent ».
        for text in ["renouveler le passeport pas pressé", "renouveler le passeport, pas urgent"] {
            let low = SiriCapture.parse(text: text, when: "sans date")
            #expect(low == .init(title: "Renouveler le passeport", priority: .low))
        }
        #expect(SiriCapture.parse(text: "payer la TVA", when: "demain, c'est urgent").priority == .urgent)
        #expect(SiriCapture.confirmation(urgent).hasPrefix("C'est noté, en urgent"))
    }

    @Test func notesRoundTrip() {
        let encoded = NotesTimeCodec.encode(minutes: 9 * 60, category: "Santé", priority: .urgent, notes: "Ordonnance")
        #expect(encoded == "⏰ 09:00\n🏷 Santé\n❗ Urgente\nOrdonnance")
        #expect(NotesTimeCodec.decode(encoded) == .init(minutes: 540, category: "Santé", priority: .urgent, notes: "Ordonnance"))
        // Normale n'écrit rien ; le marqueur seul (avec ou sans U+FE0F) suffit.
        #expect(NotesTimeCodec.encode(minutes: nil, priority: .normal, notes: "x") == "x")
        #expect(NotesTimeCodec.decode("❗\u{FE0F}\nx").priority == .urgent)
        #expect(NotesTimeCodec.decode("🔽 Basse").priority == .low)
    }
}

struct RelativeDateTests {
    let now = Date(timeIntervalSince1970: 1_791_800_000)

    @Test func relativeDurations() {
        let cases: [(String, Int)] = [
            ("rappeler Paul dans 2 heures", 120), ("dans 2h", 120), ("dans une heure", 60),
            ("dans une demi-heure", 30), ("dans un quart d’heure", 15), ("dans 20 minutes", 20),
            ("dans deux heures et demie", 150), ("dans 45 min", 45),
        ]
        for (text, minutes) in cases {
            let m = DateDetection.firstMatch(in: text, now: now)
            #expect(m?.hasTime == true, "\(text)")
            #expect(m?.date == now.addingTimeInterval(TimeInterval(minutes * 60)), "\(text)")
        }
        let m = DateDetection.firstMatch(in: "rappeler Paul dans 2 heures", now: now)!
        #expect(DateDetection.title(of: "rappeler Paul dans 2 heures", removing: m) == "rappeler Paul")
        #expect(DateDetection.firstMatch(in: "dans le garage", now: now) == nil)
    }
}
