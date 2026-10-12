import MapKit
import SwiftUI

/// Recherche d'un lieu dans Plans, avec suggestions pendant la frappe (« dentiste Alfortville », une adresse…).
struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (TaskContact) -> Void

    @State private var search = PlaceCompleter()
    @State private var resolving: MKLocalSearchCompletion?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Lieu", text: $search.query, prompt: Text("Nom, adresse ou type de lieu"))
                        .formFieldWithoutLabel()
                        .focused($focused)
                        .autocorrectionDisabled()
                        .onSubmit { if let first = search.results.first { pick(first) } }
                }
                Section {
                    ForEach(search.results, id: \.self) { result in
                        Button { pick(result) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if resolving == result { ProgressView().controlSize(.small) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(resolving != nil)
                    }
                } footer: {
                    if search.query.count >= 2, search.results.isEmpty {
                        Text("Aucun lieu trouvé. Essaie avec la ville ou le code postal.")
                    }
                }
            }
            .navigationTitle("Lieu")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .onAppear { focused = true }
        }
        #if os(macOS)
        .frame(width: 440, height: 480)
        #endif
    }

    /// Détails du lieu choisi (téléphone et site quand Plans les connaît), puis retour au détail de la tâche.
    private func pick(_ result: MKLocalSearchCompletion) {
        resolving = result
        Task {
            let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: result)).start().mapItems.first
            resolving = nil
            onPick(Self.contact(from: item, fallback: result))
            dismiss()
        }
    }

    static func contact(from item: MKMapItem?, fallback: MKLocalSearchCompletion) -> TaskContact {
        guard let item else {
            // Plans ne répond pas : on garde ce qui était affiché.
            return TaskContact(name: fallback.title, address: fallback.subtitle.isEmpty ? nil : fallback.subtitle)
        }
        let address = Self.address(of: item)
        let name = item.name ?? fallback.title
        return TaskContact(name: name,
                           // Une simple adresse : pas de doublon nom / adresse.
                           address: address == name ? nil : address,
                           phone: item.phoneNumber,
                           link: item.url)
    }

    private static func address(of item: MKMapItem) -> String? {
        let text: String?
        if #available(iOS 26, macOS 26, *) {
            text = item.address?.fullAddress
        } else {
            text = item.placemark.title
        }
        // En France, le pays n'apporte rien.
        return text?.replacingOccurrences(of: "\n", with: ", ")
            .replacingOccurrences(of: #",\s*France$"#, with: "", options: .regularExpression)
    }
}

/// Suggestions de Plans pour le texte tapé.
@Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { results = self.completer.results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { results = [] }
    }
}
