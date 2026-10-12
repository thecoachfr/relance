import SwiftData
import SwiftUI

/// Icône de la barre des menus, avec le nombre de tâches en retard.
struct MenuBarLabel: View {
    let status: MenuBarStatus

    var body: some View {
        if status.overdue > 0 {
            // Le nombre seul se lit mal en VoiceOver : on le dit en clair.
            Label("\(status.overdue)", systemImage: "checklist")
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Relance, \(status.overdue) en retard")
        } else {
            Image(systemName: "checklist").accessibilityLabel("Relance")
        }
    }
}

/// Fenêtre de la barre des menus : saisie rapide, puis les tâches en retard et du jour.
struct MenuBarView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed && $0.dueDay != nil })
    private var dated: [TaskItem]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if auth.isSignedIn {
                capture
                Divider()
                TimelineView(.everyMinute) { context in tasks(now: context.date) }
            } else {
                Text("Connecte-toi à Google dans la fenêtre de Relance.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
            Divider()
            footer
        }
        .frame(width: 360)
    }

    // MARK: - Saisie rapide

    private var capture: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Nouvelle tâche", text: $text, prompt: Text("Appeler le garage demain 15 h"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(add)
            Text(parsed.map { "↩ Ajouter · " + $0.summary } ?? "La date et l'heure sont reconnues dans la phrase.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private var parsed: QuickCapture? { QuickCapture(text) }

    private func add() {
        guard let capture = parsed else { return }
        _ = store.add(title: capture.title, day: capture.day, minutes: capture.minutes, priority: capture.priority)
        text = ""
    }

    // MARK: - Tâches du jour

    @ViewBuilder private func tasks(now: Date) -> some View {
        let groups = MacTaskList.group(dated.filter { $0.isOverdue(now: now) || Calendar.current.isDateInToday($0.dueDay!) }, now: now)
        if groups.isEmpty {
            Label("Rien pour aujourd'hui", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groups, id: \.title) { group in
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        ForEach(group.items) { MenuTaskRow(item: $0, now: now, open: open) }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func open(_ item: TaskItem) {
        store.openedTaskID = item.localID
        openWindow(id: MacAppDelegate.mainWindowID)
        NSApp.activate()
    }

    private var footer: some View {
        HStack {
            Button("Ouvrir Relance") {
                openWindow(id: MacAppDelegate.mainWindowID)
                NSApp.activate()
            }
            Spacer()
            if store.isSyncing { ProgressView().controlSize(.small) }
            Menu {
                Button("Synchroniser") { Task { await store.sync() } }
                SettingsLink { Text("Réglages…") }
                Divider()
                Button("Quitter Relance") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Plus")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Une tâche dans la barre des menus : le rond coche, le titre ouvre la fenêtre.
private struct MenuTaskRow: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    let now: Date
    let open: (TaskItem) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { withAnimation { store.complete(item) } } label: {
                PriorityCircle(priority: item.priority, late: item.isOverdue(now: now))
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Marquer fait")
            .accessibilityLabel("Marquer « \(item.title) » comme faite")

            Button { open(item) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).lineLimit(1)
                    Spacer(minLength: 8)
                    if let minutes = item.dueMinutes {
                        Text(ReminderPlanner.formatTime(minutes))
                            .monospacedDigit()
                            .foregroundStyle(item.isOverdue(now: now) ? .red : .secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(hovering ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 6))
        .padding(.horizontal, 4)
        .onHover { hovering = $0 }
    }
}

/// Phrase de saisie rapide → titre, jour, heure, priorité (« Appeler le garage demain 15 h urgent »).
/// Sans date reconnue, la tâche est pour aujourd'hui, comme dans la saisie rapide de l'iPhone.
struct QuickCapture {
    var title: String
    var day: Date?
    var minutes: Int?
    var priority: TaskPriority

    init?(_ text: String, now: Date = .now) {
        let calendar = Calendar.current
        let detectedPriority = TaskPriority.detect(in: text)
        var rest = TaskPriority.removing(detectedPriority, from: text)
        let match = DateDetection.firstMatch(in: rest, now: now)
        rest = DateDetection.title(of: rest, removing: match)
        guard !rest.isEmpty else { return nil }
        title = rest
        priority = detectedPriority?.priority ?? .normal
        day = calendar.startOfDay(for: match?.date ?? now)
        if let match, match.hasTime {
            let c = calendar.dateComponents([.hour, .minute], from: match.date)
            minutes = c.hour! * 60 + c.minute!
        }
    }

    /// « Demain à 15 h · Urgente », avec le même texte que les listes.
    var summary: String {
        guard let day else { return "Sans date" }
        let calendar = Calendar.current
        let due = minutes.flatMap { calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: day) }
            ?? calendar.date(byAdding: .day, value: 1, to: day)!
        let text = DueText.long(due: due, hasTime: minutes != nil)
        return priority == .normal ? text : text + " · " + priority.rawValue
    }
}
