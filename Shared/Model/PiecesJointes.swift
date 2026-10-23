import DonneesHA
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Pièces jointes (P9-K) : préparation sur l'appareil (photo réduite, texte lu), cache local partagé avec l'extension
/// de partage (App Group), file d'envoi vers Home Assistant (`ClientFichiers`). Une pièce est citée par la tâche dès
/// qu'on la joint ; le fichier part dès que HA répond (il attend dans la file sinon, et se voit déjà sur l'appareil).
nonisolated enum PiecesJointes {
    typealias Piece = TacheHA.Piece

    /// Plus grand côté d'une photo envoyée.
    static let cotePhoto = 2048
    static let tailleMax = 10 * 1024 * 1024
    private static let fileKey = "piecesEnAttente"
    /// Préférences de l'App Group (sans `AppGroup`, absent de l'extension de partage).
    private static var defaults: UserDefaults { Groupes.defaults }

    /// `<App Group>/Pieces` : cache des fichiers (par espace), lus ou en attente d'envoi.
    static var dossier: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Groupes.app)?.appending(path: "Pieces")
    }

    static func client() -> ClientFichiers? {
        guard let url = HAConfig.url, let token = HAConfig.token, !token.isEmpty else { return nil }
        return ClientFichiers(url: url, jeton: token, espace: HAConfig.espace, cache: dossier)
    }

    /// Le fichier local de la pièce (cache), s'il y est.
    static func local(_ piece: Piece) -> URL? {
        guard let chemin = dossier?.appending(path: HAConfig.espace).appending(path: piece.id),
              FileManager.default.fileExists(atPath: chemin.path) else { return nil }
        return chemin
    }

    /// Le fichier local, lu dans HA s'il n'est pas encore sur l'appareil.
    static func fichier(_ piece: Piece) async -> URL? {
        if let local = local(piece) { return local }
        guard let client = client(), (try? await client.lire(piece.id)) != nil else { return nil }
        return local(piece)
    }

    /// Copie du fichier avec son nom et son extension (« Rendez-vous.pdf ») pour Quick Look, les vignettes et
    /// le partage : le cache range les fichiers sous leur empreinte, sans extension, et Quick Look ne sait alors
    /// pas les ouvrir (constaté le 19/10 sur un scan). Copie dans le dossier temporaire, refaite si absente.
    static func lisible(_ piece: Piece) async -> URL? {
        guard let source = await fichier(piece) else { return nil }
        let ext = UTType(mimeType: piece.type)?.preferredFilenameExtension
        var nom = (piece.nom as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        if nom.isEmpty { nom = "Pièce jointe" }
        let dossier = FileManager.default.temporaryDirectory.appending(path: "Apercu").appending(path: String(piece.id.prefix(16)))
        let cible = dossier.appending(path: ext.map { nom + "." + $0 } ?? piece.nom)
        if FileManager.default.fileExists(atPath: cible.path) { return cible }
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: cible)
            return cible
        } catch {
            return nil
        }
    }

    // MARK: - Préparation

    enum Erreur: LocalizedError {
        case tropGros, illisible
        var errorDescription: String? {
            switch self {
            case .tropGros: "Fichier trop gros : 10 Mo au plus."
            case .illisible: "Fichier illisible."
            }
        }
    }

    /// La pièce prête à joindre : photo réduite à 2 048 px en JPEG, texte lu, fichier rangé dans le cache et mis
    /// dans la file d'envoi.
    static func preparer(_ donnees: Data, nom: String, type: UTType?, source: String, now: Date = .now) throws -> Piece {
        var contenu = donnees
        var mime = type?.preferredMIMEType ?? "application/octet-stream"
        var nomFinal = nom
        if type?.conforms(to: .image) == true || (type == nil && CGImageSourceCreateWithData(donnees as CFData, nil) != nil) {
            guard let jpeg = reduire(donnees) else { throw Erreur.illisible }
            contenu = jpeg
            mime = "image/jpeg"
            nomFinal = (nom as NSString).deletingPathExtension + ".jpg"
        }
        guard contenu.count <= tailleMax else { throw Erreur.tropGros }
        let id = FichierHA.identifiant(de: contenu)
        if let dossier {
            let chemin = dossier.appending(path: HAConfig.espace).appending(path: id)
            try FileManager.default.createDirectory(at: chemin.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contenu.write(to: chemin, options: .atomic)
        }
        let piece = Piece(id: id, nom: nomFinal, type: mime, taille: contenu.count,
                          ajouteLe: TacheHA.timestamp(now), source: source, texte: texte(contenu, type: mime))
        mettreEnAttente(piece)
        return piece
    }

    /// Photo réduite (plus grand côté 2 048 px, orientation appliquée), en JPEG qualité 0,8.
    static func reduire(_ donnees: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: cotePhoto,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let sortie = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sortie, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? sortie as Data : nil
    }

    /// Début du texte de la pièce : Vision pour une image, PDFKit pour un PDF (le texte d'un PDF scanné sans texte :
    /// Vision sur sa première page). `nil` si rien n'est lu.
    static func texte(_ donnees: Data, type: String) -> String? {
        var texte: String?
        if type.hasPrefix("image/"), let source = CGImageSourceCreateWithData(donnees as CFData, nil) {
            texte = SharedPhoto.text(in: source)
        } else if type == "application/pdf", let pdf = PDFDocument(data: donnees) {
            texte = pdf.string
            if (texte ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count < 20, let page = pdf.page(at: 0) {
                let image = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox)
                #if os(macOS)
                let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                #else
                let cg = image.cgImage
                #endif
                if let cg, let png = Self.png(cg), let source = CGImageSourceCreateWithData(png as CFData, nil) {
                    texte = SharedPhoto.text(in: source)
                }
            }
        }
        let propre = texte?.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
        guard let propre, !propre.isEmpty else { return nil }
        return String(propre.prefix(Piece.longueurTexte))
    }

    private static func png(_ image: CGImage) -> Data? {
        let sortie = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sortie, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? sortie as Data : nil
    }

    // MARK: - File d'envoi

    /// Identifiants en attente d'envoi (partagés avec l'extension de partage).
    static var enAttente: [String: [String: String]] {
        defaults.dictionary(forKey: fileKey) as? [String: [String: String]] ?? [:]
    }

    static func mettreEnAttente(_ piece: Piece) {
        var file = enAttente
        file[piece.id] = ["nom": piece.nom, "type": piece.type]
        defaults.set(file, forKey: fileKey)
    }

    /// Envoie les pièces en attente ; celles qui échouent restent dans la file. Renvoie le nombre envoyé.
    @discardableResult
    static func envoyerEnAttente() async -> Int {
        guard let client = client() else { return 0 }
        var envoyees = 0
        for (id, info) in enAttente {
            guard let chemin = dossier?.appending(path: HAConfig.espace).appending(path: id),
                  let contenu = try? Data(contentsOf: chemin) else {
                retirerDeLaFile(id)  // fichier local perdu : rien à envoyer
                continue
            }
            if await Journal.essayer(.reseau, "Envoi d'une pièce jointe", {
                try await client.envoyer(contenu, nom: info["nom"] ?? "fichier", type: info["type"] ?? "application/octet-stream")
            }) != nil {
                retirerDeLaFile(id)
                envoyees += 1
            }
        }
        return envoyees
    }

    private static func retirerDeLaFile(_ id: String) {
        var file = enAttente
        file[id] = nil
        defaults.set(file, forKey: fileKey)
    }
}
