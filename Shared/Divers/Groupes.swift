import Foundation

/// Identifiants partagés entre les cibles, définis une seule fois (checklist F3) : ce fichier est compilé par toutes
/// (app, Mac, widgets, partage, montre, complication ; voir les listes de `project.yml`).
/// Les mêmes valeurs sont déclarées dans les droits (`project.yml`, `entitlements`) : les deux doivent rester d'accord.
nonisolated enum Groupes {
    /// App Group de l'app et de ses extensions. La montre a le même identifiant, mais un conteneur à elle.
    static let app = "group.fr.alexandrefau.relance"

    /// Groupe de trousseau commun à l'app iPhone et à son extension de partage (connexion Google, jeton HA).
    /// Préfixe = ID d'équipe (`$(AppIdentifierPrefix)` dans les droits, que le code ne peut pas lire).
    static let trousseauPartage = "GD6W292ZXP.fr.alexandrefau.relance.shared"

    /// Préférences de l'App Group (préférences propres à l'appli s'il est indisponible, par exemple sans signature).
    static var defaults: UserDefaults { UserDefaults(suiteName: app) ?? .standard }
}
