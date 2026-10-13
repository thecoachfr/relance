import SwiftUI

/// Dictée d'une tâche : « appeler le garage vendredi 15 h ». La date est repérée dans la phrase ;
/// sinon on propose Aujourd'hui / Demain / Sans date.
struct WatchAddView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var choice: DayChoice = .today

    private enum DayChoice: String, CaseIterable, Identifiable {
        case today = "Aujourd'hui", tomorrow = "Demain", none = "Sans date"
        var id: String { rawValue }
    }

    var body: some View {
        let match = DateDetection.firstMatch(in: text)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Une app SwiftUI ne peut pas ouvrir la dictée seule. Depuis watchOS 26, elle se choisit
                // avec le bouton en bas à droite de l'écran de saisie ; la montre retient ensuite ce mode.
                // Plus rapide : Siri (« nouvelle tâche dans Aiguillage ») ou le bouton Action.
                TextField("Que faut-il faire ?", text: $text, prompt: Text("Toucher, puis Dictée en bas à droite"),
                          axis: .vertical)
                    .lineLimit(1...5)

                if let match {
                    Label(DueText.long(due: dueInstant(match), hasTime: match.hasTime), systemImage: "calendar")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !text.isEmpty {
                    // Une ligne « Échéance · Aujourd'hui » qui ouvre la liste : la roue est trop petite ici.
                    Picker("Échéance", selection: $choice) {
                        ForEach(DayChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                }

                Button("Ajouter") { save(match) }
                    .buttonStyle(.borderedProminent)
                    .disabled(DateDetection.title(of: text, removing: match).isEmpty)
            }
        }
        .navigationTitle("Nouvelle tâche")
    }

    /// Même convention que l'iPhone : sans heure, l'échéance est la fin du jour.
    private func dueInstant(_ match: DateDetection.Match) -> Date {
        let calendar = Calendar.current
        if match.hasTime { return match.date }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: match.date))!
    }

    private func save(_ match: DateDetection.Match?) {
        let spoken = TaskPriority.detect(in: text)
        let title = TaskPriority.removing(spoken, from: DateDetection.title(of: text, removing: match))
        guard !title.isEmpty else { return }
        let priority = spoken?.priority ?? .normal
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let match {
            store.add(title: title, due: match.hasTime ? match.date : calendar.startOfDay(for: match.date), hasTime: match.hasTime, priority: priority)
        } else {
            switch choice {
            case .today: store.add(title: title, due: today, hasTime: false, priority: priority)
            case .tomorrow: store.add(title: title, due: calendar.date(byAdding: .day, value: 1, to: today), hasTime: false, priority: priority)
            case .none: store.add(title: title, due: nil, hasTime: false, priority: priority)
            }
        }
        dismiss()
    }
}
