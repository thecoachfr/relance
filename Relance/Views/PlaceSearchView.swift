import MapKit
import SwiftUI

/// Recherche d'un lieu dans Plans, avec suggestions pendant la frappe (« dentiste Alfortville », une adresse…).
struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (TaskContact) -> Void

    @State private var search = PlaceCompleter()
    @State private var resolving: MKLocalSearchCompletion?
    /// Choix d'un point : `true` = partir de ma position, de près.
    @State private var pointPicker: Bool?
    @FocusState private var focused: Bool

    private func choisir(_ contact: TaskContact) {
        onPick(contact)
        dismiss()
    }

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
                // Mes lieux (P9-H2) : la maison et mes lieux habituels, en un toucher.
                if search.query.isEmpty {
                    let lieux = MesLieux.cached()
                    let habituels = lieux.groupes.flatMap(\.lieux)
                    if lieux.domicile != nil || !habituels.isEmpty {
                        Section("Mes lieux") {
                            if let maison = lieux.domicile {
                                Button { choisir(MesLieux.contact(maison)) } label: {
                                    Label(maison.nom, systemImage: "house.fill")
                                }
                            }
                            ForEach(habituels) { lieu in
                                Button { choisir(MesLieux.contact(lieu)) } label: {
                                    Label(lieu.nom, systemImage: "mappin")
                                }
                            }
                        }
                    }
                }
                // Un spot photo, un banc, un point de vue : un point plutôt qu'une adresse.
                if search.query.isEmpty {
                    Section {
                        #if os(iOS)
                        Button { pointPicker = true } label: {
                            Label("Ma position", systemImage: "location.fill")
                        }
                        #endif
                        Button { pointPicker = false } label: {
                            Label("Choisir sur la carte", systemImage: "mappin.and.ellipse")
                        }
                    }
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
            .navigationDestination(isPresented: Binding(get: { pointPicker != nil }, set: { if !$0 { pointPicker = nil } })) {
                PointPickerView(startsAtMyPosition: pointPicker ?? false) { contact in
                    onPick(contact)
                    dismiss()
                }
            }
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
        var name = item.name ?? fallback.title
        // Une simple adresse (« 67 rue X » puis « 67 rue X, 94140 Ville ») : le nom est l'adresse complète.
        if let address, address.lowercased().hasPrefix(name.lowercased()) { name = address }
        return TaskContact(name: name,
                           address: address,
                           phone: item.phoneNumber,
                           link: item.url)
    }

    static func address(of item: MKMapItem) -> String? {
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

/// Choix d'un point sur la carte : on déplace la carte sous une épingle fixe (comme dans Plans), le nom est
/// proposé d'après le point et reste modifiable. Le point exact est gardé dans le lien Plans de la ligne 📍.
struct PointPickerView: View {
    /// Partir de ma position, de près (« Ma position ») ; sinon une vue plus large du même endroit.
    let startsAtMyPosition: Bool
    let onPick: (TaskContact) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var name = ""
    /// Nom tapé par l'utilisateur : on ne le remplace plus par celui du point.
    @State private var nameEdited = false
    @State private var address: String?
    @State private var lookup: Task<Void, Never>?
    @State private var locationManager = CLLocationManager()

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
        }
        .mapControls {
            #if os(iOS)
            MapUserLocationButton()
            #endif
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            center = context.region.center
            describe(context.region.center)
        }
        // L'épingle reste au centre : sa pointe marque le point choisi.
        .overlay {
            Image(systemName: "mappin")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.red)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .offset(y: -17)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Nom du lieu", text: Binding(get: { name }, set: { name = $0; nameEdited = true }),
                          prompt: Text("Nom du lieu (pont, belvédère…)"))
                    .font(.headline)
                    .textFieldStyle(.roundedBorder)
                Text(address ?? center.map { Self.coordinates($0) } ?? "Déplace la carte sous l'épingle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button {
                    guard let center else { return }
                    onPick(Self.contact(name: name, address: address, at: center))
                } label: {
                    Text("Utiliser ce point").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(center == nil)
            }
            .padding()
            .background(.regularMaterial)
        }
        .navigationTitle(startsAtMyPosition ? "Ma position" : "Choisir un point")
        .inlineNavigationTitle()
        .onAppear {
            #if os(iOS)
            if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() }
            // De près pour « Ma position », plus large pour chercher un point autour.
            let span = startsAtMyPosition ? 0.002 : 0.02
            if let here = locationManager.location?.coordinate {
                position = .region(MKCoordinateRegion(center: here, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
            } else {
                position = .userLocation(fallback: .automatic)
            }
            #endif
        }
    }

    /// Nom et adresse proposés d'après le point (après un court délai : la carte bouge encore).
    private func describe(_ coordinate: CLLocationCoordinate2D) {
        lookup?.cancel()
        lookup = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let found = await Self.reverseGeocode(coordinate)
            guard !Task.isCancelled else { return }
            address = found.address
            if !nameEdited { name = found.name ?? "" }
        }
    }

    static func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> (name: String?, address: String?) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26, macOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else { return (nil, nil) }
            let address = item.address?.shortAddress ?? item.address?.fullAddress
            return (item.name, address.map(Self.cleaned))
        }
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return (nil, nil) }
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let city = [placemark.postalCode, placemark.locality].compactMap { $0 }.joined(separator: " ")
        let address = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
        return (placemark.areasOfInterest?.first ?? placemark.name, address.isEmpty ? nil : address)
    }

    private static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: ", ")
            .replacingOccurrences(of: #",\s*France$"#, with: "", options: .regularExpression)
    }

    static func coordinates(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    /// Le lieu : nom (ou l'adresse, sinon « Point sur la carte »), adresse approximative, lien Plans du point.
    static func contact(name: String, address: String?, at c: CLLocationCoordinate2D) -> TaskContact {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? (address ?? "Point sur la carte") : trimmed
        return TaskContact(name: title, address: address,
                           link: TaskContact.mapsLink(name: title, latitude: c.latitude, longitude: c.longitude))
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
