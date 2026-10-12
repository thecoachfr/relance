import SwiftUI

/// Réglages › Relances : horaires communs, puis un profil par priorité (divulgation progressive :
/// les détails ne se voient qu'en ouvrant une priorité).
struct ReminderSettingsView: View {
    @Environment(TaskStore.self) private var store
    @State private var settings = ReminderSettings()
    @State private var loaded = false

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

            Section("Horaires") {
                TimeRow(title: "Résumé du matin", minutes: $settings.morning)
                TimeRow(title: "Relance de midi", minutes: $settings.midday)
                TimeRow(title: "Relance du soir", minutes: $settings.evening)
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
                Text("Pour une tâche avec une heure et une adresse : Relance calcule le trajet avec Plans et te prévient quand il faut partir. L'adresse de départ reste sur cet appareil.")
            }

            Section {
                Toggle("Week-end calme", isOn: $settings.calmWeekends)
            } footer: {
                Text("Le samedi et le dimanche, seules l'heure prévue et les tâches urgentes relancent.")
            }
        }
        .navigationTitle("Relances")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings = store.scheduler.settings
            loaded = true
        }
        .onChange(of: settings) {
            guard loaded else { return }
            store.scheduler.settings = settings
            Task { await store.reschedule() }
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
                Picker("Activité en direct", selection: $profile.liveActivity) {
                    Text("Dès le jour prévu").tag(ReminderProfile.LiveActivity.always)
                    Text("2 h avant").tag(ReminderProfile.LiveActivity.upcoming)
                    Text("Jamais").tag(ReminderProfile.LiveActivity.never)
                }
            }

            Section {
                Button("Rétablir les réglages d'origine") { profile = .defaults(for: priority) }
                    .disabled(profile == .defaults(for: priority))
            }
        }
        .navigationTitle(priority.rawValue)
        .navigationBarTitleDisplayMode(.inline)
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
