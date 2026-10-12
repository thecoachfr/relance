import SwiftUI

/// Détail d'une tâche dans la colonne de droite (iPad) : chaque modification est enregistrée
/// aussitôt, sans bouton OK, comme dans les apps Apple sur grand écran.
struct TaskDetailView: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDay = false
    @State private var day = Date.now
    @State private var hasTime = false
    @State private var time = Date.now
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Titre", text: $title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                // L'information clé, juste sous le titre.
                if let due = item.dueInstant(), !item.isCompleted {
                    Label(DueText.long(due: due, hasTime: item.dueMinutes != nil),
                          systemImage: item.isOverdue() ? "exclamationmark.circle.fill" : "clock")
                        .foregroundStyle(item.isOverdue() ? .red : .secondary)
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...)
            }
            Section("Échéance") {
                Toggle("Date", isOn: $hasDay)
                if hasDay {
                    DatePicker("Jour", selection: $day, displayedComponents: .date)
                    Toggle("Heure", isOn: $hasTime)
                    if hasTime {
                        DatePicker("À", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }
            }
            Section {
                Button(item.isCompleted ? "Marquer à faire" : "Marquer fait",
                       systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                    item.isCompleted ? store.reopen(item) : store.complete(item)
                }
                .keyboardShortcut(.return, modifiers: .command)
                if !item.isCompleted {
                    Button("Reporter d'une heure", systemImage: "clock") {
                        store.snooze(item, until: .now.addingTimeInterval(3600))
                    }
                    .keyboardShortcut("l", modifiers: .command)
                    Button("Demain matin", systemImage: "sunrise") { store.moveToTomorrow(item) }
                }
                Button("Supprimer", systemImage: "trash", role: .destructive) { store.delete(item) }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        // Le titre est déjà le premier champ : pas de doublon dans la barre.
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
        .onChange(of: item.localID) { loaded = false; load() }
        .onChange(of: hasDay) { save() }
        .onChange(of: day) { save() }
        .onChange(of: hasTime) { save() }
        .onChange(of: time) { save() }
        // Texte : enregistré à la sortie du champ ou de la tâche, pas à chaque frappe (chaque enregistrement synchronise).
        .onSubmit { save() }
        .onDisappear { save() }
    }

    private func load() {
        title = item.title
        notes = item.notes
        hasDay = item.dueDay != nil
        day = item.dueDay ?? .now
        hasTime = item.dueMinutes != nil
        let minutes = item.dueMinutes ?? 9 * 60
        time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)!
        loaded = true
    }

    private func save() {
        guard loaded, !item.isTrashed, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minutes = hasDay && hasTime ? c.hour! * 60 + c.minute! : nil
        let newDay = hasDay ? Calendar.current.startOfDay(for: day) : nil
        guard title != item.title || notes != item.notes || newDay != item.dueDay || minutes != item.dueMinutes else { return }
        store.update(item, title: title, notes: notes, day: newDay, minutes: minutes)
    }
}
