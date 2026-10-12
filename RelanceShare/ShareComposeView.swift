import SwiftUI

/// Fiche d'ajout depuis la feuille de partage : titre prérempli, échéance et priorité lues dans le message.
/// Elle reste courte : le message complet part dans les notes, le tri range la catégorie.
struct ShareComposeView: View {
    let original: String
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var day: Date?
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    @State private var priority = TaskPriority.normal
    @State private var body_ = ""
    @State private var proposedTitle = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title, axis: .vertical)
                        .font(.headline)
                } footer: {
                    if !body_.isEmpty {
                        Text(body_).lineLimit(4)
                    }
                }

                Section("Échéance") {
                    Picker("Jour", selection: dayChoice) {
                        Text("Aujourd'hui").tag(DayChoice.today)
                        Text("Demain").tag(DayChoice.tomorrow)
                        Text("Autre").tag(DayChoice.other)
                        Text("Sans date").tag(DayChoice.none)
                    }
                    .pickerStyle(.segmented)
                    if dayChoice.wrappedValue == .other {
                        DatePicker("Date", selection: Binding(get: { day ?? .now }, set: { day = Calendar.current.startOfDay(for: $0) }),
                                   in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    }
                    if day != nil {
                        Toggle("Heure", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Section("Priorité") {
                    Picker("Priorité", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Nouvelle tâche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Ajouter") { Task { await add() } }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private enum DayChoice: Hashable { case today, tomorrow, other, none }

    private var dayChoice: Binding<DayChoice> {
        Binding {
            let calendar = Calendar.current
            guard let day else { return .none }
            if calendar.isDateInToday(day) { return .today }
            if calendar.isDateInTomorrow(day) { return .tomorrow }
            return .other
        } set: { choice in
            let today = Calendar.current.startOfDay(for: .now)
            switch choice {
            case .today: day = today
            case .tomorrow: day = Calendar.current.date(byAdding: .day, value: 1, to: today)
            case .other: day = day ?? Calendar.current.date(byAdding: .day, value: 2, to: today)
            case .none: day = nil
            }
        }
    }

    private func load() {
        let draft = SharedMessage.draft(from: original)
        title = draft.title
        proposedTitle = draft.title
        day = draft.day
        priority = draft.priority
        body_ = draft.body
        if let m = draft.minutes {
            hasTime = true
            time = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now)!
        }
    }

    /// Directement chez Google (la vigie réveille ensuite l'iPhone) ; sinon file d'attente pour l'app.
    private func add() async {
        sending = true
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minutes = day != nil && hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : nil
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = SharedMessage.notes(original: original, titleEdited: cleanTitle != proposedTitle)
        let fields: [String: Any] = [
            "title": cleanTitle,
            "notes": NotesTimeCodec.encode(minutes: minutes, priority: priority, notes: notes),
            "due": TasksAPI.due(fromDay: day) ?? NSNull(),
        ]
        let session = GoogleRefreshSession.shared
        let sent: Bool
        if session.isAvailable {
            let api = TasksAPI(token: { try await session.validAccessToken() })
            sent = await Self.within(seconds: 8) { (try? await api.insert(fields)) != nil }
        } else {
            sent = false
        }
        if !sent {
            PendingShares.add(.init(title: cleanTitle, notes: notes, day: day, minutes: minutes, priority: priority))
        }
        onDone()
    }

    /// Une feuille de partage ne doit pas rester bloquée : sans réponse de Google, on passe par la file d'attente.
    private static func within(seconds: Double, _ operation: @escaping @Sendable () async -> Bool) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await operation() }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
