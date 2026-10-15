import DonneesHA
import Foundation

/// Réglages du stockage des tâches dans Home Assistant (intégration `donnees_apps`, espace `aiguillage`).
///
/// Rien de tout cela n'est dans le dépôt (public) : l'URL est gardée dans l'App Group, le jeton de
/// l'utilisateur HA `apps-perso` dans le trousseau partagé avec l'extension de partage.
nonisolated enum HAConfig {
    static let espace = "aiguillage"
    /// Conteneur iCloud du fallback (instantané quand HA est injoignable).
    static let iCloudContainer = "iCloud.fr.alexandrefau.relance"
    static let keychainService = "ha-donnees-apps"
    static let keychainAccount = "apps-perso"

    #if os(macOS)
    /// Sur Mac, le premier groupe de trousseau de l'app (pas d'extension de partage).
    static let keychainGroup: String? = nil
    #else
    /// Groupe partagé avec l'extension de partage (le même que `GoogleRefreshSession.sharedAccessGroup`).
    static let keychainGroup: String? = "GD6W292ZXP.fr.alexandrefau.relance.shared"
    #endif

    /// Même App Group que `AppGroup` (non repris ici : l'extension de partage n'a pas SwiftData).
    static let appGroup = "group.fr.alexandrefau.relance"
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    private static let urlKey = "ha.url"
    private static let activeKey = "ha.active"
    private static let deviceKey = "ha.device"

    /// URL de Home Assistant (Nabu Casa ou réseau local), sans chemin.
    static var url: URL? {
        get { defaults.string(forKey: urlKey).flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: urlKey) }
    }

    static var token: String? {
        Trousseau.lire(service: keychainService, compte: keychainAccount, groupeAcces: keychainGroup)
    }

    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        Trousseau.ecrire(token, service: keychainService, compte: keychainAccount, groupeAcces: keychainGroup)
    }

    static func deleteToken() {
        Trousseau.supprimer(service: keychainService, compte: keychainAccount, groupeAcces: keychainGroup)
    }

    /// Les tâches sont dans HA (et non plus dans Google Tasks) sur cet appareil.
    static var isActive: Bool {
        get { defaults.bool(forKey: activeKey) }
        set { defaults.set(newValue, forKey: activeKey) }
    }

    static var isConfigured: Bool { url != nil && token?.isEmpty == false }

    /// Accepte « https://xxx.ui.nabu.casa », « xxx.ui.nabu.casa/ » ou une adresse locale ; garde l'origine seule.
    static func normalizedURL(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let c = URLComponents(string: t), let scheme = c.scheme, let host = c.host, !host.isEmpty,
              scheme == "https" || scheme == "http" else { return nil }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = c.port
        return origin.url
    }

    /// Nom de l'émetteur (`modifie_par`) et du fichier d'instantané : stable pour l'appareil,
    /// commun à l'app et à ses extensions (même base locale).
    static var device: String {
        if let saved = defaults.string(forKey: deviceKey) { return saved }
        let suffix = UUID().uuidString.prefix(4).lowercased()
        let name = "\(platform)-aiguillage-\(suffix)"
        defaults.set(name, forKey: deviceKey)
        return name
    }

    private static var platform: String {
        #if os(macOS)
        "mac"
        #elseif os(watchOS)
        "montre"
        #else
        ProcessInfo.processInfo.isiOSAppOnMac ? "mac" : (isPad ? "ipad" : "iphone")
        #endif
    }

    #if os(iOS)
    private static var isPad: Bool {
        // Sans UIKit (les extensions n'y ont pas toujours accès sur le fil voulu) : le modèle suffit.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated.hasPrefix("iPad")
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.hasPrefix("iPad")
    }
    #endif

    /// Base locale de l'espace, dans l'App Group (partagée par l'app et ses extensions).
    static func databaseURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "DonneesHA/\(espace).sqlite")
    }

    /// Le synchroniseur de l'espace ; `nil` si HA n'est pas réglé. À appeler une fois par processus.
    /// `withFallback` : l'instantané iCloud demande la capacité iCloud Documents (app iPhone, iPad, Mac).
    @MainActor
    static func makeSynchroniser(withFallback: Bool) async -> Synchroniseur? {
        guard let url, let token, !token.isEmpty, let file = databaseURL(),
              let base = try? BaseLocale(fichier: file) else { return nil }
        // `url(forUbiquityContainerIdentifier:)` peut bloquer : hors du fil principal.
        let fallback = withFallback
            ? await Task.detached { ICloudFallback.conteneur(identifiant: iCloudContainer) }.value
            : nil
        return Synchroniseur(espace: espace, appareil: device, base: base,
                             serveur: HAClient(url: url, jeton: token), fallback: fallback)
    }
}
