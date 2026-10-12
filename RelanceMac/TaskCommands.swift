import SwiftUI

/// Menus Fichier et Tâche : les raccourcis du Mac (⌘N, ⌘↩, ⌘L, ⌘R, ⌘⌫).
struct TaskCommands: Commands {
    let store: TaskStore
    @FocusedValue(\.selectedTask) private var task
    @FocusedValue(\.deleteTask) private var deleteTask

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouvelle tâche") {
                MacAppDelegate.showMainWindow()
                store.showQuickAdd = true
            }
            .keyboardShortcut("n")
        }
        CommandMenu("Tâche") {
            Button(task?.isCompleted == true ? "Remettre à faire" : "Marquer fait") {
                guard let task else { return }
                task.isCompleted ? store.reopen(task) : store.complete(task)
            }
            .keyboardShortcut(.return)
            .disabled(task == nil)

            Button("Reporter d'une heure") {
                if let task { store.snooze(task, until: .now.addingTimeInterval(3600)) }
            }
            .keyboardShortcut("l")
            .disabled(task == nil || task?.isCompleted == true)

            Button("Demain matin") {
                if let task { store.moveToTomorrow(task) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(task == nil || task?.isCompleted == true)

            Picker("Priorité", selection: Binding(
                get: { task?.priority ?? .normal },
                set: { if let task { store.setPriority(task, $0) } })) {
                ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(task == nil)

            Divider()

            Button("Supprimer") {
                if let task { deleteTask?(task) }
            }
            .keyboardShortcut(.delete)
            .disabled(task == nil)

            Divider()

            Button("Synchroniser") { Task { await store.sync() } }
                .keyboardShortcut("r")
        }
    }
}
