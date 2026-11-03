import SwiftUI

/// Réglages › Diagnostic batterie : rapports quotidiens de MetricKit et réveils de l'app (plan P9-E).
struct DiagnosticView: View {
    @State private var reports: [EnergyMetrics.Report] = []
    @State private var wakes: [(day: String, counts: [String: Int])] = []
    @State private var exportURL: URL?
    @State private var actuelMo = Empreinte.megaoctets()
    @State private var sessions = JournalSessions()

    var body: some View {
        let maintenant = Date.now
        let jour = sessions.bilan(depuis: Calendar.current.startOfDay(for: maintenant))
        let semaine = sessions.bilan(depuis: maintenant.addingTimeInterval(-7 * 86_400))
        let arrets = sessions.arrets(depuis: maintenant.addingTimeInterval(-7 * 86_400))
        Form {
            Section {
                LabeledContent("Maintenant", value: Self.mo(actuelMo))
                LabeledContent("Pic du jour", value: Self.mo(jour.picMo))
                LabeledContent("Pic sur 7 jours", value: Self.mo(semaine.picMo))
                LabeledContent("À l'écran sur 7 jours", value: SessionEcran.texteDuree(semaine.tempsEcran))
                LabeledContent("Arrêts inattendus à l'écran", value: arrets.isEmpty ? "Aucun" : "\(arrets.count)")
                ForEach(arrets.prefix(5), id: \.debut) { s in
                    Text("\(s.debut, format: .dateTime.day().month().hour().minute()) : pic \(Self.mo(s.picMo)), \(SessionEcran.texteDuree(s.duree))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Mémoire")
            } footer: {
                Text("Empreinte mesurée toutes les 10 s, seulement app à l'écran. Un arrêt inattendu : l'app a été arrêtée à l'écran (limite de mémoire ou plantage).")
            }

            Section {
                if wakes.isEmpty {
                    Text("Aucun réveil compté").foregroundStyle(.secondary)
                }
                ForEach(wakes, id: \.day) { day in
                    LabeledContent(Self.dayTitle(day.day)) {
                        Text(EnergyMetrics.Wake.allCases.map { "\(day.counts[$0.rawValue] ?? 0) \(Self.short($0))" }
                            .joined(separator: " · "))
                    }
                    .font(.footnote)
                }
            } header: {
                Text("Réveils en arrière-plan")
            } footer: {
                Text("Pushs de la vigie reçus et entrées dans une zone de rappel à l'approche, par jour.")
            }

            Section {
                if reports.isEmpty {
                    Text("Aucun rapport pour l'instant").foregroundStyle(.secondary)
                }
                ForEach(reports, id: \.self) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.begin, format: .dateTime.weekday(.wide).day().month())
                            .font(.subheadline.weight(.semibold))
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                            row("À l'écran", Self.duration(report.foregroundSeconds))
                            row("Arrière-plan", Self.duration(report.backgroundSeconds))
                            row("Position (arrière-plan)", Self.duration(report.backgroundLocationSeconds))
                            row("Position demandée", Self.duration(report.locationSeconds))
                            row("Processeur", Self.duration(report.cpuSeconds))
                            row("Réseau", "\(Self.megabytes(report.wifiMegabytes)) Wi-Fi · \(Self.megabytes(report.cellularMegabytes)) cellulaire")
                        }
                        .font(.footnote)
                    }
                }
            } header: {
                Text("Rapports quotidiens")
            } footer: {
                Text("iOS livre au plus un rapport par jour (MetricKit), le premier environ 24 h après l'installation. Rien ne quitte l'appareil, sauf si tu exportes.")
            }

            Section {
                if let exportURL {
                    ShareLink("Exporter les mesures", item: exportURL)
                }
            } footer: {
                Text("Un fichier JSON avec les résumés, les réveils et les rapports bruts de MetricKit.")
            }
        }
        .navigationTitle("Diagnostic batterie")
        .inlineNavigationTitle()
        .task {
            SuiviEcran.shared.mesurer()
            actuelMo = Empreinte.megaoctets()
            sessions = SuiviEcran.shared.journal
            reports = EnergyMetrics.reports()
            wakes = EnergyMetrics.wakes().sorted { $0.key > $1.key }.map { (day: $0.key, counts: $0.value) }
            exportURL = EnergyMetrics.exportFile()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private static func short(_ wake: EnergyMetrics.Wake) -> String {
        switch wake {
        case .push: "push"
        case .zone: "zone"
        case .visite: "arrêt"
        case .trace: "tracé"
        }
    }

    private static func dayTitle(_ key: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month())
    }

    private static func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
    }

    private static func mo(_ valeur: Double) -> String { valeur > 0 ? "\(Int(valeur.rounded())) Mo" : "—" }

    private static func megabytes(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))) + " Mo"
    }
}
