import Foundation
import Testing
@testable import Relance

/// Rendez-vous lu dans un texte (P9-L4) : SMS de rappel, e-mail, carton photographié.
struct RendezVousTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.locale = Locale(identifier: "fr_FR")
        return c
    }()

    func day(_ d: Int, _ m: Int, _ y: Int = 2026) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 18))! }

    @Test func smsDeRappelDoctolib() {
        let sms = """
        Rappel : RDV le mardi 4 novembre 2026 à 14h30 avec Dr Rabii Berrezgaoui (dentiste), \
        114 rue Édouard Vaillant, 94140 Alfortville. Tél : 01 43 78 87 05. Doctolib
        """
        let rdv = SharedAppointment.detect(in: sms, now: now, calendar: calendar)
        #expect(rdv?.title == "Rendez-vous chez le dentiste")
        #expect(rdv?.day == day(4, 11))
        #expect(rdv?.minutes == 14 * 60 + 30)
        #expect(rdv?.phone == "01 43 78 87 05")
        #expect(rdv?.address?.contains("114 rue Édouard Vaillant") == true)
        #expect(rdv?.placeName == "Dr Rabii Berrezgaoui")
    }

    @Test func cartonEnChiffres() {
        let carton = "Cabinet de kinésithérapie\nProchaine séance\n06/11 à 9h\nTel 06.75.08.26.53"
        let rdv = SharedAppointment.detect(in: carton, now: now, calendar: calendar)
        #expect(rdv?.title == "Séance de kiné")
        #expect(rdv?.day == day(6, 11))
        #expect(rdv?.minutes == 9 * 60)
        #expect(rdv?.phone == "06 75 08 26 53")
    }

    @Test func sansAnneeLeMoisPasseEstLAnProchain() {
        let rdv = SharedAppointment.detect(in: "Convocation AG le 12/02 à 18h30", now: now, calendar: calendar)
        #expect(rdv?.day == day(12, 2, 2027))
        #expect(rdv?.title == "Assemblée générale")
    }

    @Test func pasUnRendezVous() {
        // Une date sans indice de rendez-vous : rien (une facture, une recette).
        #expect(SharedAppointment.detect(in: "Facture du 04/11/2026, total 32 €", now: now, calendar: calendar) == nil)
        // Un rendez-vous passé : rien.
        #expect(SharedAppointment.detect(in: "RDV dentiste le 02/10/2026 à 10h", now: now, calendar: calendar) == nil)
    }

    /// Carton du dentiste scanné (19/10) : « 17ʰ20 » écrit à la main, lu « +20 » sur la page puis « 17+20 » dans la
    /// bande relue à côté de « Heure: » (`SharedPhoto.text`).
    @Test func cartonManuscrit() {
        let lu = """
        Rendez-vous
        Date:
        22/10
        Heure:
        +20
        Date:
        Heure:
        Merci de prévenir par téléphone au
        s 48 heures à l'avance
        01 43 78 8
        05
        Heure: 17+20
        """
        let rdv = SharedAppointment.detect(in: lu, now: now, calendar: calendar)
        #expect(rdv?.day == day(22, 10))
        #expect(rdv?.minutes == 17 * 60 + 20)
        #expect(SharedAppointment.labeledTime(in: "Heure : 9h") == 9 * 60)
        #expect(SharedAppointment.labeledTime(in: "48 heures à l'avance") == nil)
        // Deuxième lecture du même scan : « 17+20 » sur une ligne seule, « Heure: +20 » à côté de l'étiquette.
        let autre = "Rendez-vous | Date: | 22/10 | Heure: | 01 43 78 8 | 17+20 | $ 48 heures à l'avance | Heure: +20"
        #expect(SharedAppointment.detect(in: autre, now: now, calendar: calendar)?.minutes == 17 * 60 + 20)
        #expect(SharedAppointment.looseTime(in: "48 heures à l'avance, +20") == nil)
        #expect(SharedAppointment.looseTime(in: "vers 9 h") == 9 * 60)
        #expect(SharedPhoto.isFormLabel("Heure:") && SharedPhoto.isFormLabel("Date :") && !SharedPhoto.isFormLabel("Heure: 17h"))
    }

    @Test func telephoneInternational() {
        #expect(SharedAppointment.phone(in: "Appeler le +33 6 12 34 56 78") == "06 12 34 56 78")
    }
}
