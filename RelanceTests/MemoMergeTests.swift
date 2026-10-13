import Foundation
import Testing
@testable import Relance

@Suite("Mémo : ajout sans doublon")
struct MemoMergeTests {
    @Test func sameSubjectIgnoresCaseAndAccents() {
        #expect(MemoMerge.sameSubject("Dentiste", " dentiste "))
        #expect(MemoMerge.sameSubject("Kiné", "kine"))
        #expect(!MemoMerge.sameSubject("Dentiste", "Kiné"))
    }

    @Test func mergeAddsOnlyNewParts() {
        let existing = "12 rue de la Paix, 75002 Paris — 01 23 45 67 89"
        #expect(MemoMerge.merged(existing, adding: "12 rue de la Paix, 75002 Paris — catégorie Santé")
                == "12 rue de la Paix, 75002 Paris — 01 23 45 67 89 — catégorie Santé")
        #expect(MemoMerge.merged(existing, adding: "01 23 45 67 89") == nil)
        #expect(MemoMerge.merged("", adding: "ouvert le samedi") == "ouvert le samedi")
    }

    @Test func draftFromPlace() {
        let contact = TaskContact(name: "Dr Claire Martin", address: "12 rue de la Paix, 75002 Paris",
                                  phone: "01 23 45 67 89", link: URL(string: "https://example.com/rdv"))
        let draft = MemoMerge.draft(contact: contact, category: "Santé", tags: [])
        #expect(draft.title == "Dr Claire Martin")
        #expect(draft.details == "12 rue de la Paix, 75002 Paris — 01 23 45 67 89 — https://example.com/rdv — catégorie Santé")
        let parking = MemoMerge.draft(contact: TaskContact(name: "Résidence Exemple", address: "1 rue X, 75001 Paris"),
                                      category: "Administratif", tags: ["SCI", "Travaux"])
        #expect(parking.details == "1 rue X, 75001 Paris — catégorie Administratif, tags SCI, Travaux")
    }

    @Test func placeLineWritesAddressOnceWhenNameIsItsStart() {
        let contact = TaskContact(name: "1 rue Exemple", address: "1 rue Exemple, 75001 Paris")
        #expect(contact.line == "📍 1 rue Exemple, 75001 Paris")
    }

    @Test func draftFromAnyTask() {
        let notes = "Code d'accès 4521, demander le gardien\n🎙 Dicté : appeler le syndic\n📍 Résidence Exemple · 1 rue X, 75001 Paris"
        let draft = MemoMerge.draft(title: "Syndic de la résidence", notes: notes, category: "Administratif", tags: ["SCI"])
        #expect(draft.title == "Syndic de la résidence")
        #expect(draft.details == "Code d'accès 4521, demander le gardien — Résidence Exemple, 1 rue X, 75001 Paris — catégorie Administratif, tag SCI")
    }
}

@Suite("Mémo : partage depuis une autre app")
struct MemoShareDraftTests {
    @Test func noteFirstLineIsSubject() {
        let d = MemoShareDraft.draft(text: "Comptable\nCabinet Exemple, 1 rue X, 75001 Paris\n01 23 45 67 89", urls: [], pageTitle: nil)
        #expect(d.title == "Comptable")
        #expect(d.details == "Cabinet Exemple, 1 rue X, 75001 Paris — 01 23 45 67 89")
    }

    @Test func webPageUsesPageTitle() {
        let d = MemoShareDraft.draft(text: "", urls: ["https://www.example.com/expo"], pageTitle: "Expo photo — Musée Exemple")
        #expect(d.title == "Expo photo — Musée Exemple")
        #expect(d.details == "https://www.example.com/expo")
        let bare = MemoShareDraft.draft(text: "", urls: ["https://www.example.com/expo"], pageTitle: nil)
        #expect(bare.title == "example.com")
    }

    @Test func contactCard() {
        let c = MemoShareDraft.Contact(name: "Claire Exemple", organization: "Cabinet Exemple", jobTitle: "Comptable",
                                       address: "1 rue X, 75001 Paris", phone: "01 23 45 67 89", email: nil, url: nil)
        let d = MemoShareDraft.draft(contact: c)
        #expect(d.title == "Claire Exemple")
        #expect(d.details == "Comptable, Cabinet Exemple — 1 rue X, 75001 Paris — 01 23 45 67 89")
    }

    @Test func notesCollaborationLink() {
        #expect(MemoShareDraft.isNotesLink("https://www.icloud.com/notes/0abcDEF"))
        #expect(!MemoShareDraft.isNotesLink("Voir https://www.icloud.com/notes/0abc demain"))
        #expect(!MemoShareDraft.isNotesLink("Comptable"))
    }

    @Test func singleAddressGoesToDetails() {
        let d = MemoShareDraft.draft(text: "1 rue Exemple, 75001 Paris", urls: [], pageTitle: nil)
        #expect(d.title.isEmpty)
        #expect(d.details == "1 rue Exemple, 75001 Paris")
        let long = MemoShareDraft.draft(text: "Code de la porte 4521, demander le gardien au rez-de-chaussée", urls: [], pageTitle: nil)
        #expect(long.title.isEmpty)
        #expect(long.details.hasPrefix("Code de la porte"))
        let titled = MemoShareDraft.draft(text: "Résidence Exemple\n1 rue Exemple, 75001 Paris", urls: [], pageTitle: nil)
        #expect(titled.title == "Résidence Exemple")
        #expect(titled.details == "1 rue Exemple, 75001 Paris")
    }

    @Test func friendCard() {
        let card = MemoShareDraft.friendCard(givenName: "Paul", familyName: "Exemple", nickname: "Paulo",
                                             phone: "06 00 00 00 00", address: "1 rue X, 75001 Paris", note: "ami, catégorie Perso")
        #expect(card.title == "Paul Exemple (Paulo)")
        #expect(card.details == "surnom Paulo — 06 00 00 00 00 — 1 rue X, 75001 Paris — ami, catégorie Perso")
        let plain = MemoShareDraft.friendCard(givenName: "Léa", familyName: "", nickname: nil, phone: nil, address: nil, note: "")
        #expect(plain.title == "Léa")
        #expect(plain.details.isEmpty)
    }

    @Test func friendCardWithBirthday() {
        let card = MemoShareDraft.friendCard(givenName: "Paul", familyName: "Exemple", nickname: nil, phone: nil, address: nil,
                                             birthday: DateComponents(month: 3, day: 7), note: "ami")
        #expect(card.details == "anniversaire le 07/03 — ami")
    }

}

@Suite("À trier")
struct TriageRuleTests {
    @Test func datedLaterWithoutTimeIsNotToTriage() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        #expect(TaskItem(title: "Sans date").needsTriage(now: .now))
        #expect(TaskItem(title: "Aujourd'hui sans heure", dueDay: today).needsTriage(now: .now))
        #expect(TaskItem(title: "Hier sans heure", dueDay: calendar.date(byAdding: .day, value: -1, to: today)).needsTriage(now: .now))
        #expect(!TaskItem(title: "Dans un mois sans heure", dueDay: calendar.date(byAdding: .day, value: 30, to: today)).needsTriage(now: .now))
        #expect(!TaskItem(title: "Aujourd'hui à 15 h", dueDay: today, dueMinutes: 900).needsTriage(now: .now))
    }
}
