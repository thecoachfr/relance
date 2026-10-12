import SwiftUI

/// Petite étiquette colorée de catégorie (texte + symbole : la couleur n'est jamais seule porteuse du sens).
struct CategoryChip: View {
    let name: String
    /// Sur le fond d'accent d'une ligne sélectionnée, la couleur de la catégorie ne se lit plus : pastille blanche.
    var onSelection = false

    var body: some View {
        let category = TaskCategory(name: name)
        let color = category?.color ?? .gray
        ChipContent(text: name, symbol: category?.symbol ?? "tag")
            .font(.caption.weight(.medium))
            .chipStyle(onSelection ? .white : color, onSelection: onSelection)
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
    var onSelection = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(onSelection ? .white : color.mix(with: scheme == .dark ? .white : .black, by: scheme == .dark ? 0.3 : 0.45))
            .background(color.opacity(onSelection ? 0.2 : scheme == .dark ? 0.22 : 0.12), in: .capsule)
    }
}

extension View {
    func chipStyle(_ color: Color, onSelection: Bool = false) -> some View {
        modifier(ChipStyle(color: color, onSelection: onSelection))
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

/// Filtre de catégorie ou de tag (« #SCI »), partagé par « À faire » et « À trier » (mémorisé sur l'appareil).
struct CategoryFilterMenu: View {
    @Environment(TaskStore.self) private var store
    @Binding var filter: String

    var body: some View {
        Menu {
            Picker("Catégorie", selection: $filter) {
                Text("Toutes").tag("")
                ForEach(TaskCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.symbol).tag(category.rawValue)
                }
            }
            Picker("Tag", selection: $filter) {
                ForEach(store.knownTags(), id: \.self) { tag in
                    Text("#" + tag).tag("#" + tag)
                }
            }
        } label: {
            Label("Filtrer par catégorie ou tag",
                  systemImage: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

extension TaskItem {
    func matches(categoryFilter: String) -> Bool {
        if categoryFilter.hasPrefix("#") {
            let tag = categoryFilter.dropFirst()
            return tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        return categoryFilter.isEmpty || category == categoryFilter
    }
}
