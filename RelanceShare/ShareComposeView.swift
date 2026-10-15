import SwiftUI

/// Fiche d'ajout depuis la feuille de partage : titre prérempli, échéance et priorité lues dans le message.
/// Elle reste courte : le message complet part dans les notes, le tri range la catégorie.
struct ShareComposeView: View {
    let original: String
    @Binding var mode: ShareMode
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
    /// Envie reconnue d'après le lien (YouTube → À regarder…) ; `nil` = une tâche.
    @State private var kind: ToSee.Kind?
    /// Titre lu sur la page pendant que la fiche s'affiche.
    @State private var fetchingTitle = false

    var body: some View {
        NavigationStack {
            Form {
                if MemoShareDraft.isNotesLink(original) {
                    Section {
                        Label("Notes n'a envoyé qu'un lien vers la note. Pour en récupérer le texte : Annuler, puis dans la feuille de partage de Notes, choisir « Envoyer une copie » au lieu de « Collaborer ».",
                              systemImage: "info.circle")
                            .font(.callout)
                    }
                }
                Section {
                    HStack {
                        TextField("Titre", text: $title, axis: .vertical)
                            .font(.headline)
                        if fetchingTitle { ProgressView() }
                    }
                } footer: {
                    if !body_.isEmpty {
                        Text(body_).lineLimit(4)
                    }
                }

                Section {
                    Picker("Ranger dans", selection: $kind) {
                        Text("Tâche").tag(ToSee.Kind?.none)
                        ForEach(ToSee.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
                    }
                } footer: {
                    if kind != nil { Text("Gardé dans Envies, sans échéance ni relance.") }
                }

                if kind == nil {
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

                }

                Section("Priorité") {
                    Picker("Priorité", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(kind?.title ?? "Nouvelle tâche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .principal) {
                    ShareModePicker(mode: $mode)
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
        // Un lien (vidéo, album, article) : une envie, avec le titre de la page si on n'a partagé que le lien.
        guard let url = SharedLink.url(in: original) else { return }
        let linkOnly = draft.body.trimmingCharacters(in: .whitespacesAndNewlines) == url.absoluteString
        kind = SharedLink.kind(for: url, linkOnly: linkOnly)
        if kind != nil { day = nil }
        guard linkOnly else { return }
        fetchingTitle = true
        Task {
            if let pageTitle = await SharedLink.title(of: url), title == proposedTitle {
                title = String(pageTitle.prefix(SharedMessage.maxTitleLength * 2))
                proposedTitle = title
            }
            fetchingTitle = false
        }
    }

    /// Dans Home Assistant si l'app y range ses tâches, sinon directement chez Google (la vigie réveille
    /// ensuite l'iPhone) ; sans réponse de Google, file d'attente pour l'app.
    private func add() async {
        sending = true
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minutes = day != nil && hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : nil
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = SharedMessage.notes(original: original, titleEdited: cleanTitle != proposedTitle)
        if let kind {
            notes = ToSee.notes(notes, setting: ToSee(kind))
            day = nil
        }
        if HAConfig.isActive, await addToHA(title: cleanTitle, notes: notes, minutes: minutes) {
            return onDone()
        }
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

    /// Écrite dans la base locale partagée avec l'app (App Group) : elle part vers HA tout de suite si
    /// possible, sinon à la prochaine synchro de l'app (qui dépose aussi la copie iCloud). `false` si HA
    /// n'est pas réglé ou si la base est inaccessible.
    private func addToHA(title: String, notes: String, minutes: Int?) async -> Bool {
        guard let synchro = await HAConfig.makeSynchroniser(withFallback: false) else { return false }
        var tache = TacheHA(titre: title)
        tache.notes = notes
        tache.jour = TacheHA.jour(day)
        tache.heure = day == nil ? nil : TacheHA.heure(minutes)
        tache.priorite = priority == .normal ? nil : priority.rawValue
        guard let valeur = try? tache.valeur(),
              (try? synchro.ecrire(UUID().uuidString.lowercased(), valeur)) != nil else { return false }
        _ = await Self.within(seconds: 8) { @MainActor in
            await synchro.synchroniser()
            return true
        }
        return true
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
