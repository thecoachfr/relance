import DonneesHA
import Foundation

/// Texte lisible des erreurs du paquet DonneesHA (11/11/2026). Sans lui, le journal ne montrait que
/// « DonneesHA.ErreurHA 0 » et cachait la cause réelle (TLS refusé, délai dépassé, 5xx) que le paquet garde pourtant
/// dans `injoignable` : « Envoi du tracé précis : DonneesHA.ErreurHA 0 : Home Assistant injoignable : Une erreur SSL… ».
/// Jamais de jeton ni de contenu de tâche : le paquet n'y met que le texte de l'erreur réseau ou le code HTTP.
extension ErreurHA: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .injoignable(let cause): "Home Assistant injoignable : \(Self.court(cause))"
        case .nonAutorise: "Home Assistant refuse le jeton (HTTP 401 ou 403)"
        case .refuse(let message): "Requête refusée par Home Assistant : \(Self.court(message))"
        case .reponseInvalide(let detail): "Réponse illisible de Home Assistant : \(Self.court(detail))"
        }
    }

    private static func court(_ texte: String) -> String {
        texte.count > 160 ? String(texte.prefix(160)) + "…" : texte
    }
}
