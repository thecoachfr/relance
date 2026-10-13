import SwiftData
import SwiftUI

extension TaskStore {
    /// Range la tâche dans « À voir » (sans échéance), ou l'en sort.
    @MainActor func setToSee(_ item: TaskItem, _ toSee: ToSee?) {
        update(item, title: item.title, notes: ToSee.notes(item.notes, setting: toSee),
               day: toSee == nil ? item.dueDay : nil, minutes: toSee == nil ? item.dueMinutes : nil)
    }
}

/// Section « À voir » du détail : sans échéance, avec une période facultative (début, fin).
struct ToSeeSection: View {
    @Binding var notes: String
    /// Passer en « À voir » retire l'échéance du formulaire.
    var onEnable: () -> Void = {}

    private var toSee: ToSee? { ToSee(notes: notes) }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { toSee != nil }, set: { on in
                notes = ToSee.notes(notes, setting: on ? ToSee() : nil)
                if on { onEnable() }
            })) {
                Label("À voir, sans échéance", systemImage: "eyeglasses")
            }
            if let toSee {
                dateRow("Début", date: toSee.start) { var t = toSee; t.start = $0; set(t) }
                dateRow("Fin", date: toSee.end) { var t = toSee; t.end = $0; set(t) }
            }
        } footer: {
            if let toSee {
                Text(toSee.end == nil && toSee.start == nil
                     ? "Gardée dans « À voir », sans relance. Ajoute une période (expo, festival…) pour être prévenu au bon moment."
                     : "Prévenu à l'ouverture, quelques semaines avant la fin et le dernier week-end (Réglages › Relances › À voir).")
            } else {
                Text("Pour une expo, un film, un lieu à découvrir : gardé à part, sans relance chaque jour.")
            }
        }
    }

    private func set(_ toSee: ToSee) { notes = ToSee.notes(notes, setting: toSee) }

    private func dateRow(_ title: String, date: Date?, change: @escaping (Date?) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                if let date {
                    DatePicker(title, selection: Binding(get: { date }, set: { change(Calendar.current.startOfDay(for: $0)) }),
                               displayedComponents: .date)
                        .labelsHidden()
                }
                Toggle(title, isOn: Binding(get: { date != nil }, set: { change($0 ? Calendar.current.startOfDay(for: .now) : nil) }))
                    .labelsHidden()
            }
        }
    }
}

/// Liste « À voir » : en cours (la fin la plus proche d'abord), à venir, sans date, puis terminées.
struct ToSeeListView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed })
    private var active: [TaskItem]
    @State private var editing: TaskItem?
    @State private var adding = false
    var selection: Binding<UUID?>?

    static func groups(_ items: [TaskItem], now: Date = .now) -> [(title: String, items: [TaskItem])] {
        let today = Calendar.current.startOfDay(for: now)
        let seen = items.compactMap { item in item.toSee.map { (item, $0) } }
        let over = seen.filter { $0.1.isOver(now: now) }
        let current = seen.filter { !$0.1.isOver(now: now) && ($0.1.start.map { $0 <= today } ?? true) && $0.1.end != nil }
            .sorted { $0.1.end! < $1.1.end! }
        let upcoming = seen.filter { ($0.1.start.map { $0 > today } ?? false) && !$0.1.isOver(now: now) }
            .sorted { $0.1.start! < $1.1.start! }
        let open = seen.filter { $0.1.start.map { $0 <= today } ?? true } .filter { $0.1.end == nil }
        return [("En ce moment", current.map(\.0)), ("Bientôt", upcoming.map(\.0)),
                ("Sans date", open.map(\.0)), ("Terminé", over.map(\.0))].filter { !$0.1.isEmpty }
    }

    var body: some View {
        let groups = Self.groups(active)
        List(selection: selection ?? .constant(nil)) {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        TaskRow(item: item, isSelected: selection?.wrappedValue == item.localID) { store.complete($0) }
                            .tag(item.localID)
                            .contentShape(Rectangle())
                            .onTapGesture { if selection == nil { editing = item } else { selection?.wrappedValue = item.localID } }
                            .contextMenu {
                                Button("Vu", systemImage: "checkmark") { store.complete(item) }
                                Button("Remettre dans À trier", systemImage: "tray") { store.setToSee(item, nil) }
                            }
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Rien à voir pour l'instant", systemImage: "eyeglasses",
                                       description: Text("Une expo, un film, un lieu à découvrir : dans le détail d'une tâche, « À voir, sans échéance »."))
            }
        }
        .navigationTitle("À voir")
        .sheet(item: $editing) { TaskEditor(item: $0) }
        #if os(iOS)
        // Sur Mac, le « + » de la colonne suit déjà la section.
        .toolbar { AddTaskToolbarButton(context: .toSee, isPresented: $adding) }
        .sheet(isPresented: $adding) { QuickAddSheet(context: .toSee) }
        #endif
    }
}
