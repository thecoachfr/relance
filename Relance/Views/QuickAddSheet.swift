import SwiftUI

/// D'où la saisie rapide est ouverte : ses valeurs par défaut suivent l'onglet.
enum QuickAddContext: Equatable {
    /// À faire : pour aujourd'hui.
    case today
    /// À trier : sans date.
    case inbox
    /// Envies : sans échéance, du type du filtre, période facultative.
    case toSee(ToSee.Kind)
    /// Carte : sans date, le lieu d'abord.
    case map
}

/// Saisie rapide : une phrase, la date est reconnue dedans, des puces pour corriger.
/// Mêmes choix que le détail, dans le même ordre : À voir ou échéance (et Répéter), lieu, priorité, catégorie.
struct QuickAddSheet: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let context: QuickAddContext
    @State private var text = ""
    @State private var day: Date?
    /// Lignes 👀 / 🗓, 🔄 et 📍, comme dans les notes d'une tâche (aucune note libre ici).
    @State private var notes: String
    @State private var searchingPlace = false
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    /// Vrai dès que l'utilisateur touche les réglages : la phrase ne les écrase plus.
    @State private var manual = false
    /// « Autre » choisi : reste sélectionné même si la date choisie est aujourd'hui ou demain.
    @State private var pickOther = false
    @State private var category: String?
    @State private var priority = TaskPriority.normal

    init(context: QuickAddContext = .today, category: String? = nil) {
        self.context = context
        _day = State(initialValue: context == .today ? Calendar.current.startOfDay(for: .now) : nil)
        if case .toSee(let kind) = context {
            _notes = State(initialValue: ToSee.notes("", setting: ToSee(kind)))
        } else {
            _notes = State(initialValue: "")
        }
        _category = State(initialValue: category)
    }

    private var isToSee: Bool { ToSee(notes: notes) != nil }
    /// Type de l'envie en cours, ou celui de l'onglet.
    private var kind: ToSee.Kind {
        if let toSee = ToSee(notes: notes) { return toSee.kind }
        if case .toSee(let kind) = context { return kind }
        return .outing
    }

    /// Exemple dans le champ, selon l'onglet.
    private var placeholder: String {
        switch context {
        case .today: "Appeler le garage vendredi 15 h"
        case .inbox: "Rappeler le plombier"
        case .toSee(let kind): kind.example
        case .map: "Déposer le colis à la poste"
        }
    }
    /// Vrai dès que l'utilisateur choisit la priorité : la phrase ne la change plus.
    @State private var manualPriority = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nouvelle tâche", text: $text, prompt: Text(placeholder), axis: .vertical)
                        .formFieldWithoutLabel()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: text) { detect() }
                }
                if context == .map { ContactSection(notes: $notes, searching: $searchingPlace) }
                if !isToSee, let period {
                    Section {
                        Button {
                            notes = ToSee.notes(notes, setting: period.toSee)
                            day = nil
                            manual = true
                        } label: {
                            Label("Ranger dans « À voir », " + period.toSee.periodText, systemImage: ToSee.Kind.outing.symbol)
                        }
                    } footer: {
                        Text("Une période a été reconnue dans la phrase : c'est plutôt quelque chose à voir qu'une échéance.")
                    }
                }
                ToSeeSection(notes: $notes, kind: kind) { day = nil; manual = true }
                if !isToSee {
                Section("Échéance") {
                    Picker("Jour", selection: dayChoice) {
                        Text("Aujourd'hui").tag(DayChoice.today)
                        Text("Demain").tag(DayChoice.tomorrow)
                        Text("Autre").tag(DayChoice.other)
                        Text("Sans date").tag(DayChoice.none)
                    }
                    .pickerStyle(.segmented)

                    if dayChoice.wrappedValue == .other {
                        DatePicker("Date", selection: Binding(get: { day ?? .now }, set: { day = $0; manual = true }),
                                   in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    }
                    if day != nil {
                        Toggle("Heure", isOn: Binding(get: { hasTime }, set: { hasTime = $0; manual = true }))
                        if hasTime {
                            DatePicker("Heure", selection: Binding(get: { time }, set: { time = $0; manual = true }),
                                       displayedComponents: .hourAndMinute)
                        }
                        RecurrenceRow(notes: $notes, day: day ?? .now)
                    }
                }
                }
                if context != .map { ContactSection(notes: $notes, searching: $searchingPlace) }
                Section {
                    PriorityPicker(priority: Binding(get: { priority }, set: { priority = $0; manualPriority = true }))
                } header: {
                    Text("Priorité")
                } footer: {
                    PriorityFooter(priority: priority)
                }
                Section {
                    CategoryPicker(category: $category)
                }
            }
            .placeSearch(isPresented: $searchingPlace, notes: $notes)
            .navigationTitle(isToSee ? kind.title : "Nouvelle tâche")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter", action: save).disabled(cleanTitle.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private enum DayChoice: Hashable { case today, tomorrow, other, none }

    private var dayChoice: Binding<DayChoice> {
        Binding {
            let calendar = Calendar.current
            guard let day else { return .none }
            if pickOther { return .other }
            if calendar.isDateInToday(day) { return .today }
            if calendar.isDateInTomorrow(day) { return .tomorrow }
            return .other
        } set: { choice in
            manual = true
            pickOther = choice == .other
            let today = Calendar.current.startOfDay(for: .now)
            switch choice {
            case .today: day = today
            case .tomorrow: day = Calendar.current.date(byAdding: .day, value: 1, to: today)
            // Depuis « Aujourd'hui » ou « Demain », on part d'après-demain (sinon le choix revenait aussitôt).
            case .other:
                let current = day ?? today
                day = current > Calendar.current.date(byAdding: .day, value: 1, to: today)!
                    ? current : Calendar.current.date(byAdding: .day, value: 2, to: today)
            case .none: day = nil
            }
        }
    }

    // MARK: - Reconnaissance de la date dans la phrase

    private var detected: DateDetection.Match? { DateDetection.firstMatch(in: text) }

    /// Période écrite dans la phrase (« du 10/10 au 31/01 »).
    private var period: (range: Range<String.Index>, toSee: ToSee)? {
        ToSee.period(in: text).map { found in
            var toSee = found.toSee
            if isToSee { toSee.kind = kind }
            return (found.range, toSee)
        }
    }

    /// « Dune à regarder » : le type dit dans la phrase.
    private var spokenKind: (range: Range<String.Index>, kind: ToSee.Kind)? { ToSee.kind(in: text) }

    private func detect() {
        // « … à lire » : la phrase range une envie de ce type.
        if let spokenKind, ToSee(notes: notes)?.kind != spokenKind.kind {
            var toSee = ToSee(notes: notes) ?? ToSee()
            toSee.kind = spokenKind.kind
            notes = ToSee.notes(notes, setting: toSee)
            day = nil
        }
        // Envie : la période de la phrase remplit le début et la fin ; pas d'échéance à reconnaître.
        guard !isToSee else {
            if !manualPriority { priority = TaskPriority.detect(in: text)?.priority ?? .normal }
            if let period { notes = ToSee.notes(notes, setting: period.toSee) }
            return
        }
        // Une période n'est pas une échéance (sinon « du 10/10 » devenait l'échéance et la suite était perdue).
        if period != nil {
            if !manualPriority { priority = TaskPriority.detect(in: text)?.priority ?? .normal }
            return
        }
        if !manualPriority { priority = TaskPriority.detect(in: text)?.priority ?? .normal }
        guard !manual, let found = detected else { return }
        day = Calendar.current.startOfDay(for: found.date)
        pickOther = false
        hasTime = found.hasTime
        if found.hasTime { time = found.date }
    }

    private var cleanTitle: String {
        var title = text
        if let spokenKind { title.removeSubrange(spokenKind.range) }
        if isToSee, let period = ToSee.period(in: title) { title.removeSubrange(period.range) }
        else if !manual, period == nil, let found = detected { title.removeSubrange(found.range) }
        if !manualPriority { title = TaskPriority.removing(TaskPriority.detect(in: title), from: title) }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !cleanTitle.isEmpty else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        // Sans date, une répétition n'a pas de point de départ : on la retire.
        let kept = day == nil ? Recurrence.notes(notes, setting: nil) : notes
        _ = store.add(title: cleanTitle, day: isToSee ? nil : day,
                      minutes: hasTime && !isToSee ? (c.hour! * 60 + c.minute!) : nil,
                      category: category, priority: priority, notes: kept)
        dismiss()
    }
}

/// Bouton « + » des onglets : le même partout (plein, en haut à droite), saisie rapide selon l'onglet.
struct AddTaskToolbarButton: ToolbarContent {
    let context: QuickAddContext
    @Binding var isPresented: Bool

    private var isToSee: Bool { if case .toSee = context { true } else { false } }

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(isToSee ? "Nouvelle envie" : "Nouvelle tâche", systemImage: "plus") { isPresented = true }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
        }
    }
}
