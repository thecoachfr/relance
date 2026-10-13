import AppIntents
import SwiftUI
import WidgetKit

@main
struct RelanceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TasksWidget()
        TaskLiveActivity()
        NewTaskControl()
    }
}

/// Centre de contrôle et bouton Action : ouvre la saisie rapide en une pression.
struct NewTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "fr.alexandrefau.relance.newtask") {
            ControlWidgetButton(action: NewTaskIntent()) {
                Label("Nouvelle tâche", systemImage: "plus.circle")
            }
        }
        .displayName("Nouvelle tâche")
        .description("Note une tâche dans Aiguillage.")
    }
}
