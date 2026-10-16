import SwiftUI

/// Réglages › Relances : horaires communs, puis un profil par priorité (divulgation progressive :
/// les détails ne se voient qu'en ouvrant une priorité).
struct ReminderSettingsView: View {
    @Environment(TaskStore.self) private var store
    @State private var settings = ReminderSettings()
    @State private var loaded = false
    @State private var confirmRetriage = false
    @State private var retriage: TriageState = .idle

    var body: some View {
        Form {
            Section {
                ForEach(TaskPriority.allCases) { priority in
                    NavigationLink {
                        ReminderProfileView(priority: priority, profile: $settings[priority], times: settings)
                    } label: {
                        HStack(spacing: 12) {
                            PriorityCircle(priority: priority).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(priority.rawValue)
                                Text(ReminderSummary.text(for: settings[priority]))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Selon la priorité")
            } footer: {
                Text("Chaque tâche suit le réglage de sa priorité.")
            }

            Section {
                TimeRow(title: "Résumé du matin", minutes: $settings.morning)
                TimeRow(title: "Relance de midi", minutes: $settings.midday)
                TimeRow(title: "Relance du soir", minutes: $settings.evening)
                Toggle("Résumé du soir", isOn: $settings.eveningDigest)
                if settings.eveningDigest {
                    TimeRow(title: "À", minutes: $settings.eveningDigestTime)
                }
            } header: {
                Text("Horaires")
            } footer: {
                Text("Le résumé du soir annonce les tâches du lendemain et ce qui reste en retard. Rien n'arrive si demain est vide.")
            }

            Section {
                TimeRow(title: "De", minutes: $settings.quietStart)
                TimeRow(title: "À", minutes: $settings.quietEnd)
            } header: {
                Text("Plage silencieuse")
            } footer: {
                Text("Rien ne sonne pendant ce temps, sauf l'heure prévue d'une tâche et les reports que tu choisis.")
            }

            Section {
                Toggle("Pars maintenant", isOn: $settings.departure.enabled)
                if settings.departure.enabled {
                    TextField("Adresse de départ (domicile)", text: $settings.departure.origin, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                    Picker("Trajet", selection: $settings.departure.mode) {
                        ForEach(DepartureSettings.Mode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Marge", selection: $settings.departure.marginMinutes) {
                        ForEach([0, 5, 10, 15], id: \.self) { Text($0 == 0 ? "Aucune" : "\($0) min").tag($0) }
                    }
                }
            } header: {
                Text("Départ")
            } footer: {
                Text("Pour une tâche avec une heure et une adresse : Aiguillage calcule le trajet avec Plans et te prévient quand il faut partir. L'adresse de départ reste sur cet appareil.")
            }

            Section {
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
            } header: {
                Text("Tri par Claude")
            } footer: {
                Text(retriage.footer(single: false))
            }

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

            Section {
                Toggle("Week-end calme", isOn: $settings.calmWeekends)
            } footer: {
                Text("Le samedi et le dimanche, seules l'heure prévue et les tâches urgentes relancent.")
            }
        }
        .navigationTitle("Relances")
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

/// Profil d'une priorité.
struct ReminderProfileView: View {
    let priority: TaskPriority
    @Binding var profile: ReminderProfile
    /// Pour afficher les heures réglées en face de « Le matin », « À midi », « Le soir ».
    let times: ReminderSettings

    var body: some View {
        Form {
            Section {
                Picker("Prévenir", selection: $profile.advanceMinutes) {
                    Text("Non").tag(Int?.none)
                    ForEach([15, 60, 24 * 60], id: \.self) { Text(ReminderSummary.duration($0) + " avant").tag(Int?.some($0)) }
                }
            } header: {
                Text("Avant l'heure")
            } footer: {
                Text("Pour les tâches qui ont une heure.")
            }

            Section {
                Picker("Relancer", selection: $profile.followUpMinutes) {
                    Text("Non").tag(Int?.none)
                    ForEach([15, 30, 60, 120], id: \.self) { Text("Après " + ReminderSummary.duration($0)).tag(Int?.some($0)) }
                }
                if profile.followUpMinutes != nil {
                    Toggle("Jusqu'à ce que ce soit fait", isOn: $profile.followUpRepeats)
                }
            } header: {
                Text("Après l'heure")
            } footer: {
                if profile.followUpMinutes != nil {
                    Text(profile.followUpRepeats ? "Relance à cet intervalle jusqu'à minuit, hors plage silencieuse." : "Une seule relance.")
                }
            }

            Section {
                SlotToggle(title: "Le matin", time: times.morning, slot: .morning, profile: $profile)
                SlotToggle(title: "À midi", time: times.midday, slot: .midday, profile: $profile)
                SlotToggle(title: "Le soir", time: times.evening, slot: .evening, profile: $profile)
            } header: {
                Text("Sans heure ou en retard")
            } footer: {
                Text("Le jour prévu d'une tâche sans heure, puis chaque jour de retard.")
            }

            Section {
                Toggle("Demander l'heure", isOn: $profile.askTime)
            } footer: {
                Text("Pour une tâche datée sans heure : propose 9\u{00A0}h, 12\u{00A0}h, 15\u{00A0}h ou 18\u{00A0}h dès qu'elle arrive.")
            }

            Section("Affichage") {
                Picker("Mode Concentration", selection: $profile.breakthrough) {
                    Text("Toujours passer").tag(ReminderProfile.Breakthrough.always)
                    Text("À l'heure et le soir").tag(ReminderProfile.Breakthrough.important)
                    Text("Ne jamais passer").tag(ReminderProfile.Breakthrough.never)
                }
                #if os(iOS)
                Picker("Activité en direct", selection: $profile.liveActivity) {
                    Text("Dès le jour prévu").tag(ReminderProfile.LiveActivity.always)
                    Text("2 h avant").tag(ReminderProfile.LiveActivity.upcoming)
                    Text("Jamais").tag(ReminderProfile.LiveActivity.never)
                }
                #endif
            }

            Section {
                Button("Rétablir les réglages d'origine") { profile = .defaults(for: priority) }
                    .disabled(profile == .defaults(for: priority))
            }
        }
        .navigationTitle(priority.rawValue)
        .inlineNavigationTitle()
    }
}

private struct SlotToggle: View {
    let title: String
    let time: Int
    let slot: ReminderProfile.Slot
    @Binding var profile: ReminderProfile

    var body: some View {
        Toggle(isOn: Binding(
            get: { profile.slots.contains(slot) },
            set: { on in if on { profile.slots.insert(slot) } else { profile.slots.remove(slot) } })) {
            HStack {
                Text(title)
                Spacer()
                Text(ReminderPlanner.formatTime(time)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Heure en minutes depuis minuit, réglée avec la roue d'iOS.
/// Suggestions d'un type d'envie : interrupteur, heure, jours.
private struct SuggestionSection: View {
    let kind: ToSee.Kind
    @Binding var slot: EnvieSuggestions.Slot
    var isFirst = false
    var isLast = false

    var body: some View {
        Section {
            Toggle(isOn: $slot.enabled) {
                Label(kind.title, systemImage: kind.symbol)
            }
            if slot.enabled {
                TimeRow(title: "Heure", minutes: $slot.minutes)
                WeekdayPicker(selection: $slot.weekdays)
            }
        } header: {
            if isFirst { Text("Suggestions d'envies") }
        } footer: {
            if isLast {
                Text("Une envie de ce type, proposée sans son à cette heure les jours choisis : celle proposée il y a le plus longtemps. « Pas maintenant » l'écarte une semaine. Rien pendant la plage silencieuse, ni quand la liste est vide.")
            }
        }
    }
}

/// Jours de la semaine, du lundi au dimanche (valeurs de `Calendar` : 1 = dimanche).
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private static let days: [(Int, String, String)] = [
        (2, "L", "lundi"), (3, "M", "mardi"), (4, "M", "mercredi"), (5, "J", "jeudi"),
        (6, "V", "vendredi"), (7, "S", "samedi"), (1, "D", "dimanche"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.days, id: \.0) { day, letter, name in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(letter)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

private struct TimeRow: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)! },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes = c.hour! * 60 + c.minute! }),
                   displayedComponents: .hourAndMinute)
    }
}

/// Résumés lisibles d'un profil : « À l'heure, puis toutes les 30 min · passe la Concentration ».
enum ReminderSummary {
    static func duration(_ minutes: Int) -> String {
        switch minutes {
        case 24 * 60: "1 jour"
        case let m where m % 60 == 0: "\(m / 60) h"
        default: "\(minutes) min"
        }
    }

    static func text(for p: ReminderProfile) -> String {
        var parts: [String] = []
        if let a = p.advanceMinutes { parts.append(duration(a) + " avant") }
        parts.append(parts.isEmpty ? "À l'heure" : "à l'heure")
        if let f = p.followUpMinutes {
            parts.append(p.followUpRepeats ? "puis toutes les \(duration(f))" : "+\(duration(f))")
        }
        if p.slots.contains(.evening), !(p.followUpRepeats && p.followUpMinutes != nil) { parts.append("le soir") }
        var text = parts.joined(separator: ", ")
        if p.followUpMinutes == nil, p.slots.isEmpty, p.advanceMinutes == nil { text = "À l'heure seulement" }
        if p.breakthrough == .always { text += " · passe la Concentration" }
        return text
    }
}
