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
        // Une simple adresse : écrite une fois, et relue comme adresse (itinéraire possible).
        let street = TaskContact(name: "3 place de la Mairie, 75002 Paris", address: "3 place de la Mairie, 75002 Paris")
        #expect(street.line == "📍 3 place de la Mairie, 75002 Paris")
        #expect(TaskContact(notes: street.line)?.address == "3 place de la Mairie, 75002 Paris")
        #expect(TaskContact(notes: street.line)?.mapsURL != nil)
        // Google Maps : nom et adresse, sans doublon quand l'adresse sert de nom.
        #expect(place.googleMapsURL?.absoluteString.contains("query=Pharmacie%20du%20Centre,%203%20place") == true)
        #expect(street.googleMapsURL?.absoluteString.hasSuffix("query=3%20place%20de%20la%20Mairie,%2075002%20Paris") == true)
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

struct NearbyReminderTests {
    @Test func toggleLineHiddenFromNotes() {
        let notes = "Apporter les clés\n📍 Mairie · 1 place de la Mairie, 75002 Paris"
        let on = NearbyReminder.notes(notes, on: true)
        #expect(NearbyReminder.isOn(on))
        #expect(NoteLines.visible(on) == "Apporter les clés")
        #expect(TaskContact(notes: on)?.name == "Mairie")
        #expect(NearbyReminder.notes(on, on: false) == notes)
        #expect(!NearbyReminder.isOn(notes))
    }
}

struct ToSeeTests {
    let calendar = Calendar.current
    func day(_ d: Int, _ m: Int, _ y: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

    @Test func linesRoundTrip() {
        let expo = ToSee(start: day(10, 9, 2026), end: day(31, 1, 2027))
        #expect(expo.lines == ["👀 À voir", "🗓 Du 10/09/2026 au 31/01/2027"])
        let notes = ToSee.notes("MEP, rue de Fourcy", setting: expo)
        #expect(ToSee(notes: notes) == expo)
        #expect(NoteLines.visible(notes) == "MEP, rue de Fourcy")
        #expect(ToSee(notes: "👀 À voir\n🗓 Jusqu'au 31/01/2027") == ToSee(end: day(31, 1, 2027)))
        #expect(ToSee(notes: "👀 À voir") == ToSee())
        #expect(ToSee(notes: "rien") == nil)
        #expect(ToSee.notes(notes, setting: nil) == "MEP, rue de Fourcy")
    }

    @Test func periodInAPhrase() {
        let now = day(13, 10, 2026)
        let text = "Expo Irving Penn à la MEP du 10/10/2026 au 31/01/2027"
        let found = ToSee.period(in: text, now: now)
        #expect(found?.toSee == ToSee(start: day(10, 10, 2026), end: day(31, 1, 2027)))
        #expect(found.map { String(text[..<$0.range.lowerBound]).trimmingCharacters(in: .whitespaces) } == "Expo Irving Penn à la MEP")
        #expect(ToSee.period(in: "Festival du 10/07 au 14/07", now: now)?.toSee == ToSee(start: day(10, 7, 2026), end: day(14, 7, 2026)))
        // Fin sans année avant le début : l'année suivante.
        #expect(ToSee.period(in: "Expo du 10/10 au 31/01", now: now)?.toSee == ToSee(start: day(10, 10, 2026), end: day(31, 1, 2027)))
        #expect(ToSee.period(in: "Expo jusqu'au 31/01/2027", now: now)?.toSee == ToSee(end: day(31, 1, 2027)))
        #expect(ToSee.period(in: "Appeler le garage vendredi", now: now) == nil)
    }

    @Test func textAroundThePeriod() {
        let expo = ToSee(start: day(10, 9, 2026), end: day(31, 1, 2027))
        #expect(expo.text(now: day(13, 10, 2026)) == "Jusqu'au " + day(31, 1, 2027).formatted(.dateTime.day().month(.abbreviated)))
        #expect(expo.text(now: day(18, 1, 2027)) == "Plus que 2 semaines")
        #expect(expo.text(now: day(31, 1, 2027)) == "Dernier jour")
        #expect(expo.isOver(now: day(1, 2, 2027)))
    }
}

struct RecurrenceTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2
        return c
    }()
    func day(_ d: Int, _ m: Int, _ y: Int = 2026) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

    @Test func linesRoundTrip() {
        let rules: [Recurrence] = [.daily(every: 1), .daily(every: 2), .weekly(every: 1, weekdays: [2, 5]),
                                   .weekly(every: 2, weekdays: []), .monthlyDay(every: 1, day: 5), .monthlyDay(every: 3, day: 0),
                                   .monthlyWeekday(every: 1, ordinal: 1, weekday: 2), .monthlyWeekday(every: 1, ordinal: -1, weekday: 6),
                                   .yearly(month: 3, day: 15), .afterDone(amount: 3, unit: .month), .afterDone(amount: 2, unit: .week)]
        for rule in rules { #expect(Recurrence(line: rule.line) == rule, "\(rule.line)") }
        #expect(Recurrence.weekly(every: 1, weekdays: [5, 2]).line == "🔄 Toutes les semaines : lundi, jeudi")
        #expect(Recurrence.monthlyWeekday(every: 1, ordinal: 1, weekday: 2).line == "🔄 Tous les mois le 1er lundi")
        #expect(Recurrence.yearly(month: 3, day: 15).line == "🔄 Tous les ans le 15/03")
        #expect(NoteLines.visible(Recurrence.notes("Loyer", setting: .monthlyDay(every: 1, day: 5))) == "Loyer")
    }

    @Test func nextDays() {
        let now = day(13, 10)
        // Le 5 de chaque mois, faite le 13/10 pour le 05/10 : prochaine le 05/11.
        #expect(Recurrence.monthlyDay(every: 1, day: 5).nextDay(after: day(5, 10), done: now, calendar: calendar) == day(5, 11))
        // Dernier jour du mois.
        #expect(Recurrence.monthlyDay(every: 1, day: 0).nextDay(after: day(31, 10), done: now, calendar: calendar) == day(30, 11))
        // Lundi et jeudi : depuis le lundi 12/10 → jeudi 15/10 ; depuis le jeudi 15/10 → lundi 19/10.
        let mondayThursday = Recurrence.weekly(every: 1, weekdays: [2, 5])
        #expect(mondayThursday.nextDay(after: day(12, 10), done: day(12, 10), calendar: calendar) == day(15, 10))
        #expect(mondayThursday.nextDay(after: day(15, 10), done: day(15, 10), calendar: calendar) == day(19, 10))
        // 1er lundi du mois.
        #expect(Recurrence.monthlyWeekday(every: 1, ordinal: 1, weekday: 2).nextDay(after: day(5, 10), done: now, calendar: calendar) == day(2, 11))
        // Tous les ans.
        #expect(Recurrence.yearly(month: 3, day: 15).nextDay(after: day(15, 3), done: now, calendar: calendar) == day(15, 3, 2027))
        // Très en retard : jamais dans le passé.
        #expect(Recurrence.daily(every: 1).nextDay(after: day(1, 10), done: now, calendar: calendar) == day(14, 10))
        // Après avoir été faite : à partir du jour fait.
        #expect(Recurrence.afterDone(amount: 3, unit: .month).nextDay(after: day(1, 9), done: now, calendar: calendar) == day(13, 1, 2027))
    }
}
