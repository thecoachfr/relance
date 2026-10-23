import Foundation

/// « 0.3 (19) » : version et numéro de build (celui de Xcode Cloud / TestFlight), pour savoir ce qui est installé.
nonisolated enum AppVersion {
    static var text: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Commit compilé (7 caractères), écrit ici par Xcode Cloud (`ci_post_clone.sh`, `sed` sur cette ligne exacte) ;
    /// « local » pour un build de Xcode. Avant le 23/10 : clé `AiguillageCommit` ajoutée aux Info.plist par PlistBuddy.
    static let commit = "local"

    /// « 0.3 (19) · 96ebc91 »
    static var full: String { "\(text) · \(commit)" }
}
