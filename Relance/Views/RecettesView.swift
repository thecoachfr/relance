import SwiftUI

/// Réglages › Actions automatiques (P9-D2) : les recettes, appliquées par Home Assistant (la vigie) à chaque tâche
/// qui remplit leurs conditions, une seule fois par tâche.
struct RecettesView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        Form {
            Section {
                if store.recettes.isEmpty {
                    Text(HAConfig.isActive ? "Aucune recette pour l'instant : la vigie crée les premières à sa prochaine passe."
                                           : "Les actions automatiques demandent les tâches dans Home Assistant.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.recettes) { recette in
                    Toggle(isOn: Binding(get: { recette.active }, set: { store.setRecette(recette.id, active: $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recette.nom)
                            Text(["Si " + recette.conditions, recette.executant].filter { $0.count > 3 }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Une recette ajoute son action aux tâches qui remplissent ses conditions, une seule fois : une action que tu retires n'est pas remise. Chaque action et son résultat s'affichent dans la section Actions de la tâche.")
            }
        }
        .navigationTitle("Actions automatiques")
        .inlineNavigationTitle()
    }
}
