import QuickLook
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
    /// Réglages rares (priorité, relances, catégorie, tags, agenda, tri) : repliés par défaut, mémorisé.
    @AppStorage("ficheOptionsOuvertes") private var showMore = false
    /// Pièce jointe ou billet affiché en plein écran : un seul aperçu pour la fiche.
    @State private var apercu: URL?
    /// Fiche ouverte en feuille (iPhone) : la barre de navigation porte « Fermer » ; une action la ferme.
    var onClose: (() -> Void)? = nil

    var body: some View {
        // Ordre (P9-L3, 19/10) : l'essentiel d'abord (titre, échéance, lieu, ce que la tâche contient, actions),
        // les réglages rares dans « Plus d'options » ; Fait, Reporter et Supprimer dans la barre du bas.
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
            // Une envie n'a pas d'échéance (ni date, ni agenda), sauf une sortie réservée.
            if ToSee(notes: notes)?.kind.isDated != false {
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
                    ContexteRow(notes: $notes, hasDay: $hasDay, day: $day)
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
                    ContexteRow(notes: $notes, hasDay: $hasDay, day: $day)
                    #endif
                }
            }
            ContactSection(notes: $notes, searching: $searchingPlace, memoSource: (category, tags), title: title)
            ListeSection(item: item)
            PiecesSection(item: item, apercu: $apercu)
            // Une info (P9-P) montre son interrupteur en haut, comme une envie.
            if PourInfo.est(notes) {
                PourInfoSection(notes: $notes)
            }
            // Une envie montre sa section en haut ; « ranger dans les envies » est un réglage rare (Plus d'options).
            if ToSee(notes: notes) != nil {
                ToSeeSection(notes: $notes, availability: item.availability, pieces: item.pieces, apercu: $apercu) { hasDay = false }
            }
            ActionsSection(item: item, lien: item.envie()?.lien.flatMap(URL.init(string:)) ?? ToSee.link(in: NoteLines.visible(notes)))
            Section {
                Button {
                    withAnimation { showMore.toggle() }
                } label: {
                    HStack {
                        Label("Plus d'options", systemImage: "slider.horizontal.3")
                        Spacer()
                        if !showMore { Text(moreSummary).foregroundStyle(.secondary).lineLimit(1) }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showMore ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showMore ? "Ouvert" : "Fermé")
                .accessibilityHint("Priorité, relances, catégorie, tags, agenda, tri")
            }
            if showMore {
                Section {
                    PriorityPicker(priority: $priority)
                    TaskRemindersRow(reminders: $reminders, priority: priority)
                } header: {
                    // Sur Mac, la ligne porte déjà le nom « Priorité ».
                    #if os(iOS)
                    Text("Priorité")
                    #endif
                } footer: {
                    PriorityFooter(priority: priority, reminders: reminders, isEvent: ToSee(notes: notes)?.kind.isDated == true)
                }
                Section {
                    CategoryPicker(category: $category)
                    TagsRow(tags: $tags)
                }
                if ToSee(notes: notes)?.kind.isDated != false { CalendarSection(item: item) }
                if ToSee(notes: notes) == nil, !PourInfo.est(notes) {
                    PourInfoSection(notes: $notes) {
                        if !hasDay { day = Calendar.current.startOfDay(for: .now); hasDay = true }
                    }
                }
                if ToSee(notes: notes) == nil, !PourInfo.est(notes) {
                    ToSeeSection(notes: $notes, availability: item.availability, pieces: item.pieces, apercu: $apercu) { hasDay = false }
                }
                RetriageSection(item: item)
            }
        }
        .quickLookPreview($apercu)
        .deleteTaskConfirmation(item, isPresented: $confirmDelete) { onClose?() }
        .placeSearch(isPresented: $searchingPlace, notes: $notes)
        #if os(macOS)
        .toolbar { macActions }
        #endif
        #if os(iOS)
        .toolbar { bottomBar }
        // Raccourcis de l'iPad pour les actions rangées dans des menus (⌘L reporter d'une heure, ⌘⌫ supprimer).
        .background {
            Group {
                Button("Reporter d'une heure") { reporter(.now.addingTimeInterval(3600)) }.keyboardShortcut("l")
                Button("Supprimer") { supprimer() }.keyboardShortcut(.delete)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        // Colonne de l'iPad : le titre est déjà le premier champ, pas de barre en haut. Feuille de l'iPhone : « Fermer ».
        .toolbar(onClose == nil ? .hidden : .automatic, for: .navigationBar)
        #endif
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
        // Une sortie devenue une autre envie perd son échéance (les autres envies n'en ont pas).
        .onChange(of: ToSee(notes: notes)?.kind) { _, kind in if let kind, !kind.isDated { hasDay = false } }
        .onChange(of: ToSee(notes: notes)) { save() }
        .onChange(of: Recurrence(notes: notes)) { save() }
        .onChange(of: ContexteTache(notes: notes)) { save() }
        .onChange(of: PourInfo.est(notes)) { save() }
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

    #if os(iOS)
    /// Barre du bas (P9-L3) : Fait à gauche, Reporter au centre, le reste dans « ⋯ » (Supprimer avec confirmation
    /// si un événement d'agenda suit la tâche). Toujours visible, quelle que soit la longueur de la fiche.
    @ToolbarContentBuilder private var bottomBar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                item.isCompleted ? store.reopen(item) : store.complete(item)
                onClose?()
            } label: {
                // Icône et texte côte à côte : un `Label` seul n'affiche que l'icône dans la barre d'iOS 26.
                HStack(spacing: 6) {
                    Image(systemName: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    Text(item.isCompleted ? "Remettre à faire" : "Fait")
                }
                .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(item.isCompleted ? "Remettre à faire" : "Marquer fait")
            .tabletShortcut(.return, modifiers: .command)
            Spacer()
            if !item.isCompleted {
                Menu {
                    Button("Dans 1 h", systemImage: "clock") { reporter(.now.addingTimeInterval(3600)) }
                    if let soir = ceSoir { Button("Ce soir", systemImage: "moon") { reporter(soir) } }
                    Button("Demain matin", systemImage: "sunrise") { store.moveToTomorrow(item); onClose?() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Reporter")
                    }
                }
                .accessibilityLabel("Reporter")
                Spacer()
            }
            Menu {
                ShareLink(item: ([title] + [NoteLines.visible(notes)].filter { !$0.isEmpty }).joined(separator: "\n")) {
                    Label("Partager", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button("Supprimer", systemImage: "trash", role: .destructive) { supprimer() }
            } label: {
                Label("Plus", systemImage: "ellipsis.circle")
            }
            .accessibilityLabel("Plus d'actions")
        }
    }

    /// « Ce soir » : l'heure du soir des réglages, seulement si elle est encore à venir.
    private var ceSoir: Date? {
        let m = store.scheduler.settings.evening
        let soir = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now)!
        return soir > .now.addingTimeInterval(30 * 60) ? soir : nil
    }

    private func reporter(_ date: Date) {
        store.snooze(item, until: date)
        onClose?()
    }
    #endif

    private func supprimer() {
        if item.calendarEventID != nil { confirmDelete = true } else { store.delete(item); onClose?() }
    }

    /// Résumé de « Plus d'options » replié : ce qui n'est pas réglé par défaut.
    private var moreSummary: String {
        var parts: [String] = []
        if let category { parts.append(category) }
        if priority != .normal { parts.append(priority.rawValue) }
        if !tags.isEmpty { parts.append(tags.count == 1 ? "#\(tags[0])" : "\(tags.count) tags") }
        if reminders != nil { parts.append("Relances") }
        return parts.joined(separator: " · ")
    }

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
