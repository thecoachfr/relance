import SwiftUI

/// Catégories proposées (liste courte et fixe : le tri du matin les attribue de façon fiable).
/// Une catégorie inconnue lue dans les notes reste affichée, en gris.
nonisolated enum TaskCategory: String, CaseIterable, Identifiable, Sendable {
    case administratif = "Administratif"
    case maison = "Maison"
    case sante = "Santé"
    case achats = "Achats"
    case travail = "Travail"
    case famille = "Famille"
    case perso = "Perso"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .administratif: "doc.text"
        case .maison: "house"
        case .sante: "cross.case"
        case .achats: "cart"
        case .travail: "briefcase"
        case .famille: "figure.2.and.child.holdinghands"
        case .perso: "person"
        }
    }

    /// Couleurs système : contraste géré en clair et en sombre.
    var color: Color {
        switch self {
        case .administratif: .blue
        case .maison: .brown
        case .sante: .pink
        case .achats: .orange
        case .travail: .indigo
        case .famille: .green
        case .perso: .purple
        }
    }

    init?(name: String?) {
        guard let name, let match = Self.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { return nil }
        self = match
    }
}
