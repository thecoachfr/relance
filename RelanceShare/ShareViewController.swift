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
            let host = UIHostingController(rootView: ShareRootView(original: text, memoDraft: memo, photo: photo) { [weak self] in
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
        return source.flatMap(SharedPhoto.init(source:)) ?? SharedPhoto()
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
