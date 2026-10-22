import MapKit
import SwiftUI

/// Mes trajets (P9-M3) : une journée sur la carte (tracé, arrêts), et « Déjà venu ici ? » en touchant la carte.
/// L'historique est dans Home Assistant (`aiguillage_trajets`) ; rien n'est gardé sur l'appareil.
struct TrajetsCarteView: View {
    @State private var date = Date.now
    @State private var jour: JourTrajets?
    @State private var chargement = false
    @State private var erreur: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var noms: [Int: String] = [:]
    @State private var choixDate = false
    @State private var venu: (point: CLLocationCoordinate2D, resultat: DejaVenu?)?

    private var segments: [[CLLocationCoordinate2D]] { JourTrajets.segments(jour?.points ?? []) }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array((jour?.visites ?? []).enumerated()), id: \.offset) { i, arret in
                    Annotation(noms[arret.arrivee] ?? "Arrêt", coordinate: arret.coordinate) {
                        Text("\(i + 1)")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.orange, in: .circle)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let point = venu?.point {
                    Marker("Ici", systemImage: "questionmark", coordinate: point).tint(.purple)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .onTapGesture { ecran in
                guard let point = proxy.convert(ecran, from: .local) else { return }
                Task { await chercherVenu(point) }
            }
        }
        .safeAreaInset(edge: .bottom) { resume }
        .overlay {
            if chargement && jour == nil { ProgressView() }
        }
        .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Jour précédent", systemImage: "chevron.left") { aller(jour?.precedent, sinon: -1) }
                Spacer()
                Button("Choisir un jour", systemImage: "calendar") { choixDate = true }
                Button("Aujourd'hui") { date = .now }
                    .disabled(Calendar.current.isDateInToday(date))
                Spacer()
                Button("Jour suivant", systemImage: "chevron.right") { aller(jour?.suivant, sinon: 1) }
                    .disabled(Calendar.current.isDateInToday(date))
            }
        }
        .sheet(isPresented: $choixDate) {
            NavigationStack {
                DatePicker("Jour", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Choisir un jour")
                    .inlineNavigationTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { choixDate = false } } }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(get: { venu != nil }, set: { if !$0 { venu = nil } })) { feuilleVenu }
        .task(id: Calendar.current.startOfDay(for: date)) { await charger() }
    }

    // MARK: - Résumé de la journée

    @ViewBuilder private var resume: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let erreur {
                Label(erreur, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if let jour {
                if jour.points.isEmpty && jour.visites.isEmpty {
                    Text("Rien d'enregistré ce jour-là.").foregroundStyle(.secondary)
                } else {
                    Text(Self.resume(jour)).font(.headline)
                    ForEach(Array(jour.visites.enumerated()), id: \.offset) { i, arret in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.orange)
                            Text(noms[arret.arrivee] ?? "Arrêt")
                            Spacer()
                            Text(Self.heures(arret)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                Text("Touche la carte : « Déjà venu ici ? »").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    static func resume(_ jour: JourTrajets) -> String {
        let km = jour.km.formatted(.number.precision(.fractionLength(1)))
        let arrets = jour.visites.count
        return arrets == 0 ? "\(km) km" : "\(km) km · \(arrets) arrêt\(arrets > 1 ? "s" : "")"
    }

    /// « 9:05 – 10:30 · 1 h 25 », « depuis 18:20 » (pas encore reparti).
    static func heures(_ arret: ArretTrajet) -> String {
        let debut = arret.debut.formatted(date: .omitted, time: .shortened)
        guard let fin = arret.fin else { return "depuis \(debut)" }
        let minutes = Int(fin.timeIntervalSince(arret.debut) / 60)
        let duree = minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
        return "\(debut) – \(fin.formatted(date: .omitted, time: .shortened)) · \(duree)"
    }

    // MARK: - Déjà venu ici ?

    @ViewBuilder private var feuilleVenu: some View {
        NavigationStack {
            List {
                if let resultat = venu?.resultat {
                    if resultat.visites.isEmpty && resultat.jours.isEmpty {
                        Text("Jamais venu à moins de 150 m, d'après l'historique.").foregroundStyle(.secondary)
                    }
                    if !resultat.visites.isEmpty {
                        Section("Arrêts") {
                            ForEach(resultat.visites, id: \.arrivee) { arret in
                                Button {
                                    ouvrir(arret.debut)
                                } label: {
                                    LabeledContent(arret.debut.formatted(.dateTime.day().month(.wide).year()),
                                                   value: Self.heures(arret))
                                }
                            }
                        }
                    }
                    if !resultat.jours.isEmpty {
                        Section("Passé tout près") {
                            ForEach(resultat.jours, id: \.self) { j in
                                if let d = TrajetsService.date(jour: j) {
                                    Button(d.formatted(.dateTime.weekday(.wide).day().month(.wide).year())) { ouvrir(d) }
                                }
                            }
                        }
                    }
                } else {
                    HStack { ProgressView(); Text("Je cherche…") }
                }
            }
            .navigationTitle("Déjà venu ici ?")
            .inlineNavigationTitle()
        }
        .presentationDetents([.medium, .large])
    }

    private func ouvrir(_ jour: Date) {
        venu = nil
        date = jour
    }

    private func chercherVenu(_ point: CLLocationCoordinate2D) async {
        venu = (point, nil)
        do {
            let resultat = try await TrajetsService.dejaVenu(point)
            if venu?.point.latitude == point.latitude { venu = (point, resultat) }
        } catch {
            venu = nil
            erreur = error.localizedDescription
        }
    }

    // MARK: - Chargement

    private func aller(_ voisin: String?, sinon decalage: Int) {
        if let voisin, let d = TrajetsService.date(jour: voisin) {
            date = min(d, .now)
        } else if let d = Calendar.current.date(byAdding: .day, value: decalage, to: date) {
            date = min(d, .now)
        }
    }

    private func charger() async {
        chargement = true
        erreur = nil
        defer { chargement = false }
        do {
            let resultat = try await TrajetsService.jour(date)
            jour = resultat
            noms = [:]
            cadrer(resultat)
            await nommer(resultat.visites)
        } catch is CancellationError {
        } catch {
            jour = nil
            erreur = error.localizedDescription
        }
    }

    private func cadrer(_ jour: JourTrajets) {
        let coords = jour.points.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[2]) }
            + jour.visites.map(\.coordinate)
        guard let first = coords.first else { return }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))
        for c in coords.dropFirst() {
            rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 0, height: 0)))
        }
        // Au moins ~500 m de côté, et une marge autour du tracé.
        let cote = max(rect.width, rect.height, 4000)
        let marge = cote * 0.25
        position = .rect(MKMapRect(x: rect.midX - cote / 2 - marge, y: rect.midY - cote / 2 - marge,
                                   width: cote + 2 * marge, height: cote + 2 * marge))
    }

    /// Nom de chaque arrêt d'après Plans (au plus 10 par jour).
    private func nommer(_ arrets: [ArretTrajet]) async {
        for arret in arrets.prefix(10) {
            let trouve = await PointPickerView.reverseGeocode(arret.coordinate)
            if let nom = trouve.name ?? trouve.address { noms[arret.arrivee] = nom }
        }
    }
}
