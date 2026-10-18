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
    @State private var confirmDelete = false
    @State private var searchingPlace = false

    var body: some View {
        Form {
            Section {
                TextField("Titre", text: $title, prompt: Text("Titre"), axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .formFieldWithoutLabel()
                // L'information clé, juste sous le titre.
                if let due = item.dueInstant(), !item.isCompleted {
                    Label(DueText.long(due: due, hasTime: item.dueMinutes != nil),
                          systemImage: item.isOverdue() ? "clock.fill" : "clock")
                        .foregroundStyle(item.isOverdue() ? .red : .secondary)
                }
                TextField("Notes", text: visibleNotes, prompt: Text("Notes"), axis: .vertical)
                    .lineLimit(3...)
                    .formFieldWithoutLabel()
            }
            ProposalSection(item: item, notes: $notes)
            ContactSection(notes: $notes, searching: $searchingPlace, memoSource: (category, tags), title: title)
            // Un « À voir » n'a pas d'échéance : ni date, ni agenda.
            if ToSee(notes: notes) == nil {
                Section("Échéance") {
                    #if os(macOS)
                    // Mac : l'interrupteur et la valeur sur la même ligne, comme dans Rappels.
                    LabeledContent("Date") {
                        HStack {
                            if hasDay { DatePicker("Jour", selection: $day, displayedComponents: .date).labelsHidden() }
                            Toggle("Date", isOn: $hasDay).labelsHidden()
                        }
                    }
                    if hasDay {
                        LabeledContent("Heure") {
                            HStack {
                                if hasTime { DatePicker("À", selection: $time, displayedComponents: .hourAndMinute).labelsHidden() }
                                Toggle("Heure", isOn: $hasTime).labelsHidden()
                            }
                        }
                        if hasTime { DureeRow(item: item) }
                        RecurrenceRow(notes: $notes, day: day)
                    }
                    #else
                    Toggle("Date", isOn: $hasDay)
                    if hasDay {
                        DatePicker("Jour", selection: $day, displayedComponents: .date)
                        Toggle("Heure", isOn: $hasTime)
                        if hasTime {
                            DatePicker("À", selection: $time, displayedComponents: .hourAndMinute)
                            DureeRow(item: item)
                        }
                        RecurrenceRow(notes: $notes, day: day)
                    }
                    #endif
                }
            }
            ListeSection(item: item)
            PiecesSection(item: item)
            ToSeeSection(notes: $notes, availability: item.availability) { hasDay = false }
            if ToSee(notes: notes) == nil { CalendarSection(item: item) }
            Section {
                PriorityPicker(priority: $priority)
                TaskRemindersRow(reminders: $reminders, priority: priority)
            } header: {
                // Sur Mac, la ligne porte déjà le nom « Priorité ».
                #if os(iOS)
                Text("Priorité")
                #endif
            } footer: {
                PriorityFooter(priority: priority, reminders: reminders)
            }
            Section {
                CategoryPicker(category: $category)
                TagsRow(tags: $tags)
            }
            ActionsSection(item: item, lien: item.envie()?.lien.flatMap(URL.init(string:)) ?? ToSee.link(in: NoteLines.visible(notes)))
            RetriageSection(item: item)
            // Sur Mac, ces actions sont dans la barre d'outils et le menu Tâche.
            #if os(iOS)
            Section {
                Button(item.isCompleted ? "Marquer à faire" : "Marquer fait",
                       systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                    item.isCompleted ? store.reopen(item) : store.complete(item)
                }
                .tabletShortcut(.return, modifiers: .command)
                if !item.isCompleted {
                    Button("Reporter d'une heure", systemImage: "clock") {
                        store.snooze(item, until: .now.addingTimeInterval(3600))
                    }
                    .tabletShortcut("l", modifiers: .command)
                    Button("Demain matin", systemImage: "sunrise") { store.moveToTomorrow(item) }
                }
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    if item.calendarEventID != nil { confirmDelete = true } else { store.delete(item) }
                }
                .tabletShortcut(.delete, modifiers: .command)
            }
            #endif
        }
        .deleteTaskConfirmation(item, isPresented: $confirmDelete)
        .placeSearch(isPresented: $searchingPlace, notes: $notes)
        #if os(macOS)
        .toolbar { macActions }
        #endif
        // Le titre est déjà le premier champ : pas de doublon dans la barre.
        .hiddenNavigationBar()
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
        // Lieu ajouté, changé ou retiré (bouton) : enregistré tout de suite, comme les autres réglages.
        .onChange(of: TaskContact(notes: notes)) { save() }
        .onChange(of: NearbyReminder.choice(notes)) { save() }
        .onChange(of: ToSee(notes: notes)) { save() }
        .onChange(of: Recurrence(notes: notes)) { save() }
        // Texte : enregistré à la sortie du champ ou de la tâche, pas à chaque frappe (chaque enregistrement synchronise).
        .onSubmit { save() }
        .onDisappear { save() }
    }

    #if os(macOS)
    /// Actions de la tâche dans la barre d'outils, au-dessus du détail (comme Mail ou Rappels).
    @ToolbarContentBuilder private var macActions: some ToolbarContent {
        ToolbarItemGroup {
            Button(item.isCompleted ? "Remettre à faire" : "Marquer fait",
                   systemImage: item.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle") {
                item.isCompleted ? store.reopen(item) : store.complete(item)
            }
            .help(item.isCompleted ? "Remettre à faire (⌘↩)" : "Marquer fait (⌘↩)")
            if !item.isCompleted {
                Menu("Reporter", systemImage: "clock.arrow.circlepath") {
                    Button("Dans 1 h") { store.snooze(item, until: .now.addingTimeInterval(3600)) }
                    Button("Demain matin") { store.moveToTomorrow(item) }
                }
                .help("Reporter")
            }
            Button("Supprimer", systemImage: "trash") {
                if item.calendarEventID != nil { confirmDelete = true } else { store.delete(item) }
            }
            .help("Supprimer (⌘⌫)")
        }
    }
    #endif

    /// Le champ Notes sans les lignes techniques (lieu, agenda, message partagé), gardées à l'enregistrement.
    private var visibleNotes: Binding<String> {
        Binding { NoteLines.visible(notes) } set: { notes = NoteLines.replacingVisible(in: notes, with: $0) }
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
