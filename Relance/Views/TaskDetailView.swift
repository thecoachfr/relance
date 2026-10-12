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
    @State private var category: String?
    @State private var priority = TaskPriority.normal
    @State private var reminders: ReminderOverride?
    @State private var tags: [String] = []
    @State private var loaded = false
    /// État de la tâche au chargement : sert à ne renvoyer que ce que l'utilisateur a changé.
    @State private var base: TaskFields?

    var body: some View {
        Form {
            Section {
                TextField("Titre", text: $title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                // L'information clé, juste sous le titre.
                if let due = item.dueInstant(), !item.isCompleted {
                    Label(DueText.long(due: due, hasTime: item.dueMinutes != nil),
                          systemImage: item.isOverdue() ? "clock.fill" : "clock")
                        .foregroundStyle(item.isOverdue() ? .red : .secondary)
                }
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
        // Modifiée ailleurs (synchro, routine de tri, autre appareil) : on recharge si rien n'est en cours de saisie.
        .onChange(of: item.updatedAt) { if !hasPendingEdits { load() } }
        .onChange(of: hasDay) { save() }
        .onChange(of: day) { save() }
        .onChange(of: hasTime) { save() }
        .onChange(of: time) { save() }
        .onChange(of: category) { save() }
        .onChange(of: priority) { save() }
        .onChange(of: reminders) { save() }
        .onChange(of: tags) { save() }
        // Texte : enregistré à la sortie du champ ou de la tâche, pas à chaque frappe (chaque enregistrement synchronise).
        .onSubmit { save() }
        .onDisappear { save() }
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
        loaded = true
    }

    private var entered: TaskFields {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return TaskFields(title: title, notes: notes,
                          day: hasDay ? Calendar.current.startOfDay(for: day) : nil,
                          minutes: hasDay && hasTime ? c.hour! * 60 + c.minute! : nil,
                          category: category, priority: priority, reminders: reminders, tags: tags)
    }

    private var hasPendingEdits: Bool {
        guard let base else { return false }
        return entered.merged(base: base, current: base) != base
    }

    private func save() {
        guard loaded, let base, !item.isTrashed, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let fields = entered.merged(base: base, current: TaskFields(item))
        store.save(fields, to: item)
        self.base = TaskFields(item)
    }
}
