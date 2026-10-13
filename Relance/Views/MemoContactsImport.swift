#if os(iOS)
import Contacts
import ContactsUI
import SwiftUI

/// « Depuis Contacts… » : une fiche du mémo par proche choisi (nom, surnom, téléphone, adresse).
/// Le sélecteur d'iOS ne donne à l'app que les contacts cochés, sans accès au carnet entier.
struct MemoContactsImportView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var contacts: [CNContact] = []
    @State private var picking = true
    @State private var note = "ami, catégorie Perso"
    @State private var saving = false
    @State private var done = 0

    private var cards: [(title: String, details: String)] {
        contacts.map { c in
            MemoShareDraft.friendCard(
                givenName: c.givenName, familyName: c.familyName,
                nickname: c.isKeyAvailable(CNContactNicknameKey) ? c.nickname : nil,
                phone: c.isKeyAvailable(CNContactPhoneNumbersKey) ? c.phoneNumbers.first?.value.stringValue : nil,
                address: c.isKeyAvailable(CNContactPostalAddressesKey) ? c.postalAddresses.first.map(Self.oneLine) : nil,
                birthday: c.isKeyAvailable(CNContactBirthdayKey) ? c.birthday : nil,
                note: note)
        }
        .filter { !$0.title.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mention commune", text: $note, prompt: Text("ami, catégorie Perso"))
                } header: {
                    Text("Ajouté à chaque fiche")
                } footer: {
                    Text("Aide la routine à ranger les tâches qui les concernent (catégorie, tag).")
                }
                Section {
                    ForEach(cards, id: \.title) { card in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                            Text(card.details).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button("Choisir d'autres contacts", systemImage: "person.crop.circle.badge.plus") { picking = true }
                } header: {
                    Text(cards.isEmpty ? "Aucun contact choisi" : "\(cards.count) fiche(s)")
                } footer: {
                    Text("Un proche qui a déjà sa fiche est complété, pas doublé.")
                }
                if let error = store.memo.lastError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Depuis Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        Text("\(done)/\(cards.count)").monospacedDigit()
                    } else {
                        Button("Ajouter") { Task { await save() } }
                            .disabled(cards.isEmpty)
                    }
                }
            }
            .background(ContactPickerPresenter(isPresented: $picking) { picked in
                let known = Set(contacts.map(\.identifier))
                contacts += picked.filter { !known.contains($0.identifier) }
                if contacts.isEmpty { dismiss() }
            })
        }
    }

    private func save() async {
        saving = true
        for card in cards {
            await store.memo.remember(title: card.title, details: card.details)
            done += 1
        }
        saving = false
        if store.memo.lastError == nil { dismiss() }
    }

    private static func oneLine(_ address: CNLabeledValue<CNPostalAddress>) -> String {
        CNPostalAddressFormatter.string(from: address.value, style: .mailingAddress)
            .components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Présente le sélecteur de contacts (plusieurs à la fois) : il doit être présenté par un contrôleur,
/// il ne s'affiche pas correctement dans une feuille SwiftUI.
private struct ContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactNicknameKey, CNContactPhoneNumbersKey, CNContactPostalAddressesKey, CNContactBirthdayKey]
        DispatchQueue.main.async { host.present(picker, animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerPresenter
        init(_ parent: ContactPickerPresenter) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            parent.isPresented = false
            parent.onPick(contacts)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
            parent.onPick([])
        }
    }
}
#endif
