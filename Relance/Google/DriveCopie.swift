import Foundation
import GoogleSignIn
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Option B du plan P9-K : copie d'une pièce jointe dans Google Drive, dans le dossier « Aiguillage – Justificatifs »
/// (créé par l'app). La routine « Aiguillage · actions » (TVA), qui lit le Drive, y trouve les factures. Accès
/// `drive.file` seulement : l'app ne voit que les fichiers qu'elle a créés ; demandé à la première copie.
enum DriveCopie {
    static let scope = "https://www.googleapis.com/auth/drive.file"
    static let nomDossier = "Aiguillage – Justificatifs"
    private static let dossierKey = "driveDossierJustificatifs"

    enum Erreur: LocalizedError {
        case pasConnecte, refuse, envoi(String)
        var errorDescription: String? {
            switch self {
            case .pasConnecte: "Connecte-toi d'abord à Google (Réglages)."
            case .refuse: "Accès à Google Drive refusé."
            case .envoi(let m): "Copie dans Drive impossible : \(m)"
            }
        }
    }

    /// Copie le fichier dans le dossier des justificatifs ; renvoie l'identifiant Drive du fichier.
    @MainActor
    static func copier(_ fichier: URL, nom: String, type: String) async throws -> String {
        let jeton = try await jetonDrive()
        let dossier = try await dossierJustificatifs(jeton)
        let contenu = try Data(contentsOf: fichier)
        let limite = "aiguillage-\(UUID().uuidString)"
        let meta = try JSONSerialization.data(withJSONObject: ["name": nom, "parents": [dossier], "mimeType": type])
        var corps = Data()
        corps.append(Data("--\(limite)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        corps.append(meta)
        corps.append(Data("\r\n--\(limite)\r\nContent-Type: \(type)\r\n\r\n".utf8))
        corps.append(contenu)
        corps.append(Data("\r\n--\(limite)--\r\n".utf8))
        var r = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!)
        r.httpMethod = "POST"
        r.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        r.setValue("multipart/related; boundary=\(limite)", forHTTPHeaderField: "Content-Type")
        let (donnees, reponse) = try await URLSession.shared.upload(for: r, from: corps)
        return try identifiant(donnees, reponse)
    }

    /// Jeton avec l'accès Drive ; la première fois, Google demande l'accord d'Alexandre.
    @MainActor
    private static func jetonDrive() async throws -> String {
        guard var utilisateur = GIDSignIn.sharedInstance.currentUser else { throw Erreur.pasConnecte }
        if utilisateur.grantedScopes?.contains(scope) != true {
            #if os(iOS)
            guard let presentateur = presentateur() else { throw Erreur.refuse }
            utilisateur = try await utilisateur.addScopes([scope], presenting: presentateur).user
            #else
            guard let fenetre = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { throw Erreur.refuse }
            utilisateur = try await utilisateur.addScopes([scope], presenting: fenetre).user
            #endif
            guard utilisateur.grantedScopes?.contains(scope) == true else { throw Erreur.refuse }
        }
        return try await utilisateur.refreshTokensIfNeeded().accessToken.tokenString
    }

    /// Le dossier des justificatifs, créé au premier usage (et recréé s'il a été supprimé).
    private static func dossierJustificatifs(_ jeton: String) async throws -> String {
        if let id = UserDefaults.standard.string(forKey: dossierKey), try await existe(id, jeton) { return id }
        var r = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        r.httpMethod = "POST"
        r.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["name": nomDossier, "mimeType": "application/vnd.google-apps.folder"])
        let (donnees, reponse) = try await URLSession.shared.data(for: r)
        let id = try identifiant(donnees, reponse)
        UserDefaults.standard.set(id, forKey: dossierKey)
        return id
    }

    private static func existe(_ id: String, _ jeton: String) async throws -> Bool {
        var r = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?fields=trashed")!)
        r.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        let (donnees, reponse) = try await URLSession.shared.data(for: r)
        guard (reponse as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: donnees) as? [String: Any] else { return false }
        return (json["trashed"] as? Bool) != true
    }

    private static func identifiant(_ donnees: Data, _ reponse: URLResponse) throws -> String {
        guard let http = reponse as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              let id = json["id"] as? String else {
            let message = String(decoding: donnees.prefix(300), as: UTF8.self)
            throw Erreur.envoi(message.contains("has not been used") || message.contains("disabled")
                               ? "l'API Google Drive n'est pas activée dans le projet Google Cloud" : message)
        }
        return id
    }

    #if os(iOS)
    @MainActor
    private static func presentateur() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #endif
}
