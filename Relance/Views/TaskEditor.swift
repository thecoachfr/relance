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
    @State private var category: String?
    @State private var priority = TaskPriority.normal
    @State private var reminders: ReminderOverride?
    @State private var tags: [String] = []
    @State private var base: TaskFields?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title, axis: .vertical)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                ContactSection(notes: notes)
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
                CalendarSection(item: item)
                Section {
                    PriorityPicker(priority: $priority)
                    TaskRemindersRow(reminders: $reminders, priority: priority)
                } header: {
                    Text("Priorité")
                } footer: {
                    PriorityFooter(priority: priority, reminders: reminders)
                }
                Section {
                    CategoryPicker(category: $category)
                    TagsRow(tags: $tags)
                }
                RetriageSection(item: item)
                Section {
                    Button(item.isCompleted ? "Marquer à faire" : "Marquer fait") {
                        item.isCompleted ? store.reopen(item) : store.complete(item)
                        dismiss()
                    }
                    Button("Supprimer", role: .destructive) {
                        if item.calendarEventID != nil { confirmDelete = true } else { store.delete(item); dismiss() }
                    }
                    .deleteTaskConfirmation(item, isPresented: $confirmDelete) { dismiss() }
                }
            }
            .navigationTitle("Tâche")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let entered = TaskFields(title: title, notes: notes,
                                                 day: hasDay ? Calendar.current.startOfDay(for: day) : nil,
                                                 minutes: hasDay && hasTime ? c.hour! * 60 + c.minute! : nil,
                                                 category: category, priority: priority, reminders: reminders, tags: tags)
                        // Seuls les champs changés ici sont repris (une synchro a pu arriver pendant la saisie).
                        if let base { store.save(entered.merged(base: base, current: TaskFields(item)), to: item) }
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
        category = item.category
        priority = item.priority
        reminders = item.reminderOverride
        tags = item.tags
        hasDay = item.dueDay != nil
        day = item.dueDay ?? .now
        hasTime = item.dueMinutes != nil
        let minutes = item.dueMinutes ?? 9 * 60
        time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)!
        base = TaskFields(item)
    }
}
