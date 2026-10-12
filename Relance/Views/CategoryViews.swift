import SwiftUI

/// Petite étiquette colorée de catégorie (texte + symbole : la couleur n'est jamais seule porteuse du sens).
struct CategoryChip: View {
    let name: String

    var body: some View {
        let category = TaskCategory(name: name)
        let color = category?.color ?? .gray
        Label(name, systemImage: category?.symbol ?? "tag")
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: .capsule)
            .accessibilityLabel("Catégorie \(name)")
    }
}

/// Choix de catégorie pour les formulaires (« Aucune » + la liste fixe).
struct CategoryPicker: View {
    @Binding var category: String?

    var body: some View {
        Picker("Catégorie", selection: $category) {
            Text("Aucune").tag(String?.none)
            ForEach(TaskCategory.allCases) { category in
                Label(category.rawValue, systemImage: category.symbol).tag(Optional(category.rawValue))
            }
        }
    }
}

/// Filtre de catégorie partagé par « À faire » et « À trier » (mémorisé sur l'appareil).
struct CategoryFilterMenu: View {
    @Binding var filter: String

    var body: some View {
        Menu {
            Picker("Catégorie", selection: $filter) {
                Text("Toutes").tag("")
                ForEach(TaskCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.symbol).tag(category.rawValue)
                }
            }
        } label: {
            Label("Filtrer par catégorie",
                  systemImage: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

extension TaskItem {
    func matches(categoryFilter: String) -> Bool {
        categoryFilter.isEmpty || category == categoryFilter
    }
}
