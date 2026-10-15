import Foundation

/// « 0.3 (19) » : version et numéro de build (celui de Xcode Cloud / TestFlight), pour savoir ce qui est installé.
nonisolated enum AppVersion {
    static var text: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
