import SwiftUI

struct TaskEditor: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: TaskItem

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDay = false
    @State private var day = Date.now
    @State private var hasTime = false
    @State private var time = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title, axis: .vertical)
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
                    Button(item.isCompleted ? "Marquer à faire" : "Marquer fait") {
                        item.isCompleted ? store.reopen(item) : store.complete(item)
                        dismiss()
                    }
                    Button("Supprimer", role: .destructive) {
                        store.delete(item)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Tâche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                        store.update(item, title: title, notes: notes, day: hasDay ? day : nil,
                                     minutes: hasTime ? c.hour! * 60 + c.minute! : nil)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        title = item.title
        notes = item.notes
        hasDay = item.dueDay != nil
        day = item.dueDay ?? .now
        hasTime = item.dueMinutes != nil
        let minutes = item.dueMinutes ?? 9 * 60
        time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)!
    }
}
