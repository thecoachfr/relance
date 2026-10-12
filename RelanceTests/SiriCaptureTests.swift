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
