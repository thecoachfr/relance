import Contacts
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Point d'entrée de l'extension de partage : lit le texte (ou le lien) reçu et affiche la fiche.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let text = await Self.sharedText(from: extensionContext)
            let memo = await Self.memoDraft(from: extensionContext)
            let photo = await Self.sharedPhoto(from: extensionContext)
            let fichier = await Self.sharedFile(from: extensionContext)
            let host = UIHostingController(rootView: ShareRootView(original: text, memoDraft: memo, photo: photo, fichier: fichier) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            } onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            })
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    /// Texte d'abord (un message), sinon l'adresse du lien.
    private static func sharedText(from context: NSExtensionContext?) async -> String {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var texts: [String] = []
        var urls: [String] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                texts.append(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                urls.append(url.absoluteString)
            }
        }
        return (texts.isEmpty ? urls : texts + urls.filter { url in !texts.contains { $0.contains(url) } })
            .joined(separator: "\n")
    }

    /// Fichier partagé (PDF, image, autre) à joindre à une tâche (P9-K), 10 Mo au plus.
    private static func sharedFile(from context: NSExtensionContext?) async -> FichierPartage? {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for type in [UTType.pdf, .image, .data] {
            guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }),
                  let item = try? await provider.loadItem(forTypeIdentifier: type.identifier) else { continue }
            let nom = provider.suggestedName
            switch item {
            case let url as URL:
                guard let data = try? Data(contentsOf: url) else { return nil }
                let typeFichier = UTType(filenameExtension: url.pathExtension) ?? type
                if data.count > PiecesJointes.tailleMax {
                    // Photo en pleine définition (plus de 10 Mo) : réduite plutôt qu'écartée (28/10, la photo de
                    // produits n'arrivait pas, ni en pièce jointe ni vers la liste de courses).
                    return typeFichier.conforms(to: .image) ? reduite(data, nom: nom ?? url.lastPathComponent) : nil
                }
                return FichierPartage(donnees: data, nom: nom ?? url.lastPathComponent, type: typeFichier)
            case let data as Data:
                if data.count > PiecesJointes.tailleMax {
                    return type.conforms(to: .image) ? reduite(data, nom: nom ?? "Photo.jpg") : nil
                }
                return FichierPartage(donnees: data, nom: nom ?? "Pièce jointe", type: type)
            case let image as UIImage:
                return image.jpegData(compressionQuality: 0.9).map { FichierPartage(donnees: $0, nom: nom ?? "Capture.jpg", type: .jpeg) }
            default:
                continue
            }
        }
        return nil
    }

    /// Image trop lourde réduite à 3 000 px de côté au plus, en JPEG ; `nil` si elle est illisible.
    private static func reduite(_ data: Data, nom: String) -> FichierPartage? {
        guard let image = UIImage(data: data) else { return nil }
        let echelle = min(1, 3000 / max(image.size.width, image.size.height))
        let taille = CGSize(width: image.size.width * echelle, height: image.size.height * echelle)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: taille, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: taille)) }
            .jpegData(compressionQuality: 0.85)
        guard let jpeg, jpeg.count <= PiecesJointes.tailleMax else { return nil }
        return FichierPartage(donnees: jpeg, nom: ((nom as NSString).deletingPathExtension) + ".jpg", type: .jpeg)
    }

    /// Photo partagée depuis Photos : position et date lues dans le fichier (rien n'est gardé de l'image).
    private static func sharedPhoto(from context: NSExtensionContext?) async -> SharedPhoto? {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
              let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        let source: CGImageSource?
        switch item {
        case let url as URL: source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case let data as Data: source = CGImageSourceCreateWithData(data as CFData, nil)
        default: source = nil  // Une image sans fichier (capture) n'a pas de métadonnées.
        }
        var photo = source.flatMap(SharedPhoto.init(source:)) ?? SharedPhoto()
        // Une page de livre de recettes : son texte (lu sur l'iPhone) peut devenir une liste de courses (P9-G3).
        if let source { photo.texte = SharedPhoto.text(in: source) }
        return photo
    }

    /// Contact d'abord (fiche la plus riche), sinon texte, liens et titre de la page.
    static func memoDraft(from context: NSExtensionContext?) async -> (title: String, details: String) {
        let items = context?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        var texts: [String] = []
        var urls: [String] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.vCard.identifier),
               let data = try? await provider.loadItem(forTypeIdentifier: UTType.vCard.identifier) as? Data,
               let contact = try? CNContactVCardSerialization.contacts(with: data).first {
                return MemoShareDraft.draft(contact: Self.contact(contact))
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                texts.append(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                urls.append(url.absoluteString)
            }
        }
        // Notes : le texte arrive comme « texte du partage », pas en pièce jointe.
        let contentText = items.compactMap { $0.attributedContentText?.string }.first { !$0.isEmpty }
        if texts.isEmpty, urls.isEmpty, let contentText { texts.append(contentText) }
        // Safari : le titre de la page accompagne le lien.
        let pageTitle = texts.isEmpty ? (items.compactMap { $0.attributedTitle?.string }.first ?? contentText) : nil
        return MemoShareDraft.draft(text: texts.joined(separator: "\n"), urls: urls, pageTitle: pageTitle)
    }

    private static func contact(_ c: CNContact) -> MemoShareDraft.Contact {
        let name = CNContactFormatter.string(from: c, style: .fullName) ?? ""
        let address = c.postalAddresses.first.map {
            CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress)
                .components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return MemoShareDraft.Contact(
            name: name, organization: c.organizationName, jobTitle: c.jobTitle, address: address,
            phone: c.phoneNumbers.first?.value.stringValue, email: c.emailAddresses.first.map { $0.value as String },
            url: c.urlAddresses.first.map { $0.value as String })
    }
}

/// Fichier reçu par la feuille de partage, à joindre à une tâche (P9-K).
struct FichierPartage: Sendable {
    var donnees: Data
    var nom: String
    var type: UTType
}
