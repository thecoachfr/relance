import SwiftUI

/// Réglages › Envies (revue du 28/10, sortis de « Relances », qui faisait huit écrans) : rappels des envies datées,
/// rappel à l'approche par défaut, suggestions à heure fixe, abonnements de streaming.
struct EnviesSettingsView: View {
    @Environment(TaskStore.self) private var store
    @State private var settings = ReminderSettings()
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Toggle("À l'ouverture", isOn: $settings.toSee.atOpening)
                Picker("Avant la fin", selection: $settings.toSee.weeksBeforeEnd) {
                    Text("Non").tag(Int?.none)
                    ForEach([1, 2, 3, 4], id: \.self) { Text("\($0) semaine\($0 > 1 ? "s" : "")").tag(Int?.some($0)) }
                }
                Toggle("Le dernier week-end", isOn: $settings.toSee.lastWeekend)
                TimeRow(title: "Heure", minutes: $settings.toSee.time)
            } header: {
                Text("Envies")
            } footer: {
                Text("Pour les envies avec une période (expo, festival, film en salle). Sans période, aucune relance.")
            }

            Section {
                ForEach(Subscriptions.choices, id: \.self) { code in
                    Toggle(SharedLink.platformName(code), isOn: Binding(
                        get: { store.subscriptions.contains(code) },
                        set: { on in
                            var codes = store.subscriptions.filter { $0 != code }
                            if on { codes.append(code) }
                            store.setSubscriptions(codes)
                        }))
                }
            } header: {
                Text("Mes abonnements")
            } footer: {
                Text("Une envie à regarder disponible sur l'un d'eux affiche « Inclus dans ton abonnement ». Partagé avec tes autres appareils par Home Assistant.")
            }

            Section {
                ForEach(ToSee.Kind.allCases.filter(\.isPlace)) { kind in
                    Toggle(isOn: Binding(
                        get: { settings.toSee.nearbyKinds.contains(kind.rawValue) },
                        set: { on in
                            settings.toSee.nearbyKinds.removeAll { $0 == kind.rawValue }
                            if on { settings.toSee.nearbyKinds.append(kind.rawValue) }
                        })) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } header: {
                Text("À l'approche, par défaut")
            } footer: {
                Text("Pour ces envies avec un lieu, l'appareil qui relance te prévient en passant à moins de 200 m, sans rien activer. Chaque envie peut le couper dans sa section Lieu. Au-delà de 20 lieux, les plus proches de toi sont surveillés.")
            }

            ForEach(EnvieSuggestions.kinds) { kind in
                SuggestionSection(kind: kind, slot: Binding(
                    get: { settings.suggestions[kind]! }, set: { settings.suggestions[kind] = $0 }),
                    isFirst: kind == EnvieSuggestions.kinds.first, isLast: kind == EnvieSuggestions.kinds.last)
            }

        }
        .navigationTitle("Envies")
        .inlineNavigationTitle()
        .onAppear {
            settings = store.scheduler.settings
            loaded = true
        }
        .onChange(of: settings) {
            guard loaded else { return }
            let nearbyChanged = store.scheduler.settings.toSee.nearbyKinds != settings.toSee.nearbyKinds
            store.scheduler.settings = settings
            Task { await store.reschedule() }
            // Zones à l'approche (appareil qui relance) : recalculées avec les nouveaux types par défaut.
            if nearbyChanged { store.onTasksChanged?() }
        }
    }
}

/// « Tout retrier avec Claude » (sorti de Relances le 28/10) : catégories et tags de toutes les tâches recalculés.
struct RetrierToutSection: View {
    @Environment(TaskStore.self) private var store
    @State private var confirmRetriage = false
    @State private var retriage: TriageState = .idle

    var body: some View {
        Button {
            confirmRetriage = true
        } label: {
            HStack {
                Label("Tout retrier avec Claude", systemImage: "sparkles")
                if retriage == .sending { Spacer(); ProgressView() }
            }
        }
        .disabled(retriage == .sending)
        .confirmationDialog("Les catégories et tags actuels de toutes les tâches à faire seront remplacés.",
                            isPresented: $confirmRetriage, titleVisibility: .visible) {
            Button("Tout retrier") {
                Task {
                    retriage = .sending
                    retriage = await TriageRequest.retriage(store.activeTasks(), store: store) ? .sent : .failed
                }
            }
        }
        if retriage != .idle {
            Text(retriage.footer(single: false)).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
