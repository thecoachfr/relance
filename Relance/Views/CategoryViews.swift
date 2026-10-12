import SwiftUI

/// Petite étiquette colorée de catégorie (texte + symbole : la couleur n'est jamais seule porteuse du sens).
struct CategoryChip: View {
    let name: String

    var body: some View {
        let category = TaskCategory(name: name)
        let color = category?.color ?? .gray
        ChipContent(text: name, symbol: category?.symbol ?? "tag")
            .font(.caption.weight(.medium))
            .chipStyle(color)
            .accessibilityLabel("Catégorie \(name)")
    }
}

/// Symbole collé au texte : dans une liste, `Label` réserve une colonne d'icône trop large pour une pastille.
struct ChipContent: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(text)
        }
    }
}

/// Pastille teintée lisible : le texte coloré est assombri (clair) ou éclairci (sombre)
/// pour dépasser 4,5:1 sur son fond, même en petite taille.
struct ChipStyle: ViewModifier {
    let color: Color
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color.mix(with: scheme == .dark ? .white : .black, by: scheme == .dark ? 0.3 : 0.45))
            .background(color.opacity(scheme == .dark ? 0.22 : 0.12), in: .capsule)
    }
}

extension View {
    func chipStyle(_ color: Color) -> some View { modifier(ChipStyle(color: color)) }
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
