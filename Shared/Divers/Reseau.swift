import Foundation

/// Requêtes vers Google et Home Assistant : délai court, nouvel essai avec attente croissante quand l'échec est passager.
/// Avant : `URLSession.shared` (60 s d'attente avant d'abandonner) et aucun nouvel essai.
/// Home Assistant (23/10) : webhook (inscription aux push, trajets, tri), mémo (`MemoHA`), « Sur la TV » (`TVRemote`).
/// Le paquet DonneesHA (tâches) a sa propre session.
nonisolated enum Reseau {
    /// 15 s sans réponse : on abandonne (au lieu de 60 s) ; 60 s au plus pour une requête entière.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    static let essaisMax = 3

    /// Attente avant le nouvel essai n° `tentative` (1 = après le premier échec), ou nil s'il ne faut pas réessayer.
    /// - `rejouable` : la requête peut être renvoyée sans risque (GET, PATCH, DELETE, jeton). Un ajout (POST) ne l'est pas :
    ///   s'il a été reçu mais que la réponse s'est perdue, le renvoyer créerait un doublon ; il n'est réessayé que sur 429,
    ///   où le serveur dit explicitement n'avoir rien fait.
    static func attente(tentative: Int, statut: Int?, erreur: URLError.Code?, rejouable: Bool,
                        retryAfter: String? = nil) -> Duration? {
        guard tentative < essaisMax else { return nil }
        let passager: Bool
        switch (statut, erreur) {
        case (429?, _): passager = true
        case (let s?, _) where [500, 502, 503, 504].contains(s): passager = rejouable
        case (_, let e?) where [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed].contains(e):
            passager = rejouable
        default: passager = false   // hors ligne, 4xx, réponse illisible : réessayer tout de suite ne changerait rien
        }
        guard passager else { return nil }
        if let retryAfter, let secondes = Double(retryAfter) { return .seconds(min(max(secondes, 0), 10)) }
        return .seconds(1 << (tentative - 1))   // 1 s, puis 2 s
    }

    /// Envoie la requête ; renvoie la dernière réponse (même en erreur HTTP) ou lève la dernière erreur réseau.
    static func envoyer(_ requete: URLRequest, rejouable: Bool) async throws -> (Data, HTTPURLResponse?) {
        var tentative = 1
        while true {
            do {
                let (donnees, reponse) = try await session.data(for: requete)
                let http = reponse as? HTTPURLResponse
                if let http, let pause = attente(tentative: tentative, statut: http.statusCode, erreur: nil,
                                                 rejouable: rejouable,
                                                 retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
                    try await Task.sleep(for: pause)
                    tentative += 1
                    continue
                }
                return (donnees, http)
            } catch let erreur as URLError {
                guard let pause = attente(tentative: tentative, statut: nil, erreur: erreur.code, rejouable: rejouable)
                else { throw erreur }
                try await Task.sleep(for: pause)
                tentative += 1
            }
        }
    }
}

/// Envoi en arrière-plan qui a échoué (TLS refusé, réseau absent, Home Assistant injoignable) : on attend avant de
/// retenter, de plus en plus longtemps (2, 4, 8, 16, puis 30 min au plus), au lieu de renvoyer à chaque occasion.
/// Vécu le 03/11 : le tracé précis retentait à chaque nouveau point, 23 échecs TLS en 5 min (BATTERIE.md, 11/11).
/// Ce qui attendait d'être envoyé reste dans sa file locale.
nonisolated struct AttenteApresEchec: Codable, Equatable, Sendable {
    static let premiere: TimeInterval = 2 * 60
    static let maximum: TimeInterval = 30 * 60

    private(set) var echecs = 0
    private(set) var prochainEssai: Date?

    /// Faut-il attendre encore à `date` ?
    func doitAttendre(a date: Date) -> Bool { prochainEssai.map { date < $0 } ?? false }

    mutating func echec(a date: Date) {
        echecs += 1
        prochainEssai = date.addingTimeInterval(Self.pause(apres: echecs))
    }

    mutating func reussite() { self = AttenteApresEchec() }

    /// Attente après `echecs` échecs de suite : 2 min, puis le double à chaque fois, 30 min au plus.
    static func pause(apres echecs: Int) -> TimeInterval {
        min(premiere * pow(2, Double(min(max(echecs, 1) - 1, 10))), maximum)
    }
}
