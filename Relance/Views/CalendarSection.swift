import SwiftUI

/// « Ajouter au calendrier » pour une tâche avec date et heure ; ensuite « Dans l'agenda », ouvrir ou retirer.
struct CalendarSection: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.openURL) private var openURL
    let item: TaskItem
    @State private var error: String?
    @State private var working = false

    private var link: CalendarLink { CalendarLink.shared }

    var body: some View {
        Section {
            if item.calendarEventID != nil, link.event(for: item) != nil {
                Label("Dans l'agenda" + (link.event(for: item)?.calendar.title).map { " · \($0)" }.orEmpty,
                      systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.green)
                if let start = item.dueInstant() {
                    Button("Ouvrir dans Calendrier", systemImage: "calendar") {
                        openURL(URL(string: "calshow:\(start.timeIntervalSinceReferenceDate)")!)
                    }
                }
                Button("Retirer de l'agenda", systemImage: "calendar.badge.minus", role: .destructive) {
                    link.remove(item, taskStore: store)
                }
            } else if CalendarLink.isLinked(item.notes) {
                // Ajoutée depuis un autre appareil : l'événement existe, mais on ne le gère pas d'ici.
                Label("Dans l'agenda (ajoutée depuis un autre appareil)", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task {
                        working = true
                        error = await link.add(item, taskStore: store)
                        working = false
                    }
                } label: {
                    HStack {
                        Label("Ajouter au calendrier", systemImage: "calendar.badge.plus")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(item.dueMinutes == nil || working)
            }
        } footer: {
            if let error {
                Text(error).foregroundStyle(.red)
            } else if item.dueMinutes == nil, item.calendarEventID == nil {
                Text("Donne une heure à la tâche pour l'ajouter à l'agenda.")
            } else if item.calendarEventID == nil, !CalendarLink.isLinked(item.notes) {
                Text("Événement d'1 h dans \(link.defaultCalendarName.map { "« \($0) »" } ?? "ton agenda par défaut"), sans alerte : c'est Relance qui relance.")
            } else {
                Text("L'événement suit l'heure et le titre de la tâche.")
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

/// Suppression d'une tâche liée à un événement : on demande s'il faut aussi l'enlever de l'agenda.
struct DeleteTaskConfirmation: ViewModifier {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    @Binding var isPresented: Bool
    var onDeleted: () -> Void = {}

    func body(content: Content) -> some View {
        content.confirmationDialog("Cette tâche est dans ton agenda.", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Supprimer la tâche et l'événement", role: .destructive) {
                CalendarLink.shared.remove(item, taskStore: store, keepTask: false)
                store.delete(item)
                onDeleted()
            }
            Button("Supprimer la tâche seulement", role: .destructive) {
                store.delete(item)
                onDeleted()
            }
        }
    }
}

extension View {
    func deleteTaskConfirmation(_ item: TaskItem, isPresented: Binding<Bool>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(DeleteTaskConfirmation(item: item, isPresented: isPresented, onDeleted: onDeleted))
    }
}
