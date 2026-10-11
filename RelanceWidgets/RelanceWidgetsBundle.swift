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
            // Un lien plutôt qu'un intent maison : l'ouverture de l'app est garantie par le système.
            ControlWidgetButton(action: OpenURLIntent(URL(string: "relance://nouvelle")!)) {
                Label("Nouvelle tâche", systemImage: "plus.circle")
            }
        }
        .displayName("Nouvelle tâche")
        .description("Note une tâche dans Relance.")
    }
}
