import SwiftUI

/// Ligne « Relances » d'une tâche : « Selon la priorité », ou le réglage propre à la tâche.
struct TaskRemindersRow: View {
    @Binding var reminders: ReminderOverride?
    let priority: TaskPriority

    var body: some View {
        NavigationLink {
            TaskRemindersView(reminders: $reminders, priority: priority)
        } label: {
            LabeledContent("Relances", value: Self.summary(reminders))
        }
    }

    static func summary(_ reminders: ReminderOverride?) -> String {
        guard let line = reminders?.line else { return "Selon la priorité" }
        return String(line.dropFirst(ReminderOverride.marker.count)).trimmingCharacters(in: .whitespaces)
    }
}

/// Relances propres à une tâche (« prévenir 1 jour avant », « relancer toutes les 15 min »),
/// qui remplacent celles de sa priorité pour cette tâche seulement.
struct TaskRemindersView: View {
    @Environment(TaskStore.self) private var store
    @Binding var reminders: ReminderOverride?
    let priority: TaskPriority

    private var inherited: ReminderProfile { store.scheduler.settings[priority] }

    var body: some View {
        Form {
            Section {
                Picker("Prévenir", selection: advance) {
                    Text("Selon la priorité (\(inheritedAdvance))").tag(ReminderOverride.Advance?.none)
                    Text("Non").tag(ReminderOverride.Advance?.some(.off))
                    ForEach([15, 60, 24 * 60], id: \.self) {
                        Text(ReminderDuration.text($0) + " avant").tag(ReminderOverride.Advance?.some(.minutes($0)))
                    }
                }
            } header: {
                Text("Avant l'heure")
            } footer: {
                Text("Pour une tâche qui a une heure.")
            }

            Section("Après l'heure") {
                Picker("Relancer", selection: followUp) {
                    Text("Selon la priorité (\(inheritedFollowUp))").tag(ReminderOverride.FollowUp?.none)
                    Text("Non").tag(ReminderOverride.FollowUp?.some(.off))
                    ForEach([15, 30, 60, 120], id: \.self) {
                        Text("Une fois, après " + ReminderDuration.text($0)).tag(ReminderOverride.FollowUp?.some(.once($0)))
                    }
                    ForEach([15, 30, 60, 120], id: \.self) {
                        Text("Toutes les " + ReminderDuration.text($0)).tag(ReminderOverride.FollowUp?.some(.every($0)))
                    }
                }
            }

            if reminders != nil {
                Section {
                    Button("Revenir aux réglages de la priorité") { reminders = nil }
                } footer: {
                    Text("Les relances de la priorité \(priority.rawValue) se règlent dans Réglages › Relances.")
                }
            }
        }
        .navigationTitle("Relances")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var advance: Binding<ReminderOverride.Advance?> {
        Binding { reminders?.advance } set: { update { $0.advance = $1 }($0) }
    }

    private var followUp: Binding<ReminderOverride.FollowUp?> {
        Binding { reminders?.followUp } set: { update { $0.followUp = $1 }($0) }
    }

    /// Modifie le réglage ; revient à `nil` (« selon la priorité ») quand plus rien n'est personnalisé.
    private func update<T>(_ change: @escaping (inout ReminderOverride, T) -> Void) -> (T) -> Void {
        { value in
            var r = reminders ?? ReminderOverride()
            change(&r, value)
            reminders = r.isEmpty ? nil : r
        }
    }

    private var inheritedAdvance: String {
        inherited.advanceMinutes.map { ReminderDuration.text($0) + " avant" } ?? "non"
    }

    private var inheritedFollowUp: String {
        guard let m = inherited.followUpMinutes else { return "non" }
        return inherited.followUpRepeats ? "toutes les " + ReminderDuration.text(m) : "après " + ReminderDuration.text(m)
    }
}
