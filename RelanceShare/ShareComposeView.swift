import SwiftUI

/// Fiche d'ajout depuis la feuille de partage : titre prérempli, échéance et priorité lues dans le message.
/// Elle reste courte : le message complet part dans les notes, le tri range la catégorie.
struct ShareComposeView: View {
    let original: String
    var photo: SharedPhoto?
    var fichier: FichierPartage?
    @Binding var mode: ShareMode
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var day: Date?
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    @State private var priority = TaskPriority.normal
    @State private var body_ = ""
    @State private var proposedTitle = ""
    @State private var sending = false
    /// Envie reconnue d'après le lien (YouTube → À regarder…) ; `nil` = une tâche.
    @State private var kind: ToSee.Kind?
    /// Titre lu sur la page pendant que la fiche s'affiche.
    @State private var fetchingTitle = false
    /// Lieu lu dans un lien Plans ou Google Maps, et ce lien.
    @State private var place: SharedPlace?
    /// Rendez-vous reconnu dans le texte (P9-L4) : pas de spot photo, ni d'avertissement de position.
    @State private var appointment = false
    @State private var placeLink: URL?
    /// Envie proposée d'après la catégorie de Plans, et la sorte de lieu (« bar ») notée sur sa ligne.
    @State private var suggestion: (kind: ToSee.Kind, label: String?)?
    /// Recette (P9-G3) : lue dans la page (données schema.org), ou texte collé qui parle d'ingrédients.
    @State private var recipe: SharedRecipe?
    @State private var recipeText = false
    /// En faire une liste de courses, préparée ensuite par la routine de tri.
    @State private var asList = false
    /// Joindre le fichier partagé (P9-K), à une nouvelle tâche ou à une tâche existante (clé HA).
    @State private var joindre = false
    @State private var cible: String?
    @State private var recentes: [(cle: String, titre: String)] = []

    var body: some View {
        NavigationStack {
            Form {
                if MemoShareDraft.isNotesLink(original) {
                    Section {
                        Label("Notes n'a envoyé qu'un lien vers la note. Pour en récupérer le texte : Annuler, puis dans la feuille de partage de Notes, choisir « Envoyer une copie » au lieu de « Collaborer ».",
                              systemImage: "info.circle")
                            .font(.callout)
                    }
                }
                Section {
                    HStack {
                        TextField("Titre", text: $title, axis: .vertical)
                            .font(.headline)
                        if fetchingTitle { ProgressView() }
                    }
                } footer: {
                    if !body_.isEmpty {
                        Text(body_).lineLimit(4)
                    }
                }

                if let photo, !photo.hasLocation, !recipeText, !appointment {
                    Section {
                        Label("Cette photo n'a pas de position. Dans Photos, touche Options en haut de la feuille de partage et active « Lieu », ou ajoute le lieu ensuite dans la tâche.",
                              systemImage: "location.slash")
                            .font(.callout)
                    }
                }
                if let place {
                    Section("Lieu") {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                let details = [suggestion?.label?.capitalizedFirst, place.address == place.name ? nil : place.address, place.phone]
                                    .compactMap { $0 }.joined(separator: " · ")
                                if !details.isEmpty {
                                    Text(details).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }
                }

                if HAConfig.isActive, recipe != nil || recipeText {
                    Section {
                        Toggle("Liste de courses", systemImage: "cart", isOn: $asList)
                    } header: {
                        Text("Recette")
                    } footer: {
                        if let recipe {
                            Text("\(recipe.ingredients.count) ingrédients trouvés\(recipe.parts.map { " pour \($0) parts" } ?? "")."
                                 + " Claude en fera une liste à cocher, quantités indicatives, dans la minute.")
                        } else {
                            Text("Claude lira les ingrédients du texte et en fera une liste à cocher, quantités indicatives.")
                        }
                    }
                }

                // Photo de produits (P9-R) : vers la liste de courses la plus récente, articles proposés par Claude.
                if HAConfig.isActive, let fichier, fichier.type.conforms(to: .image), !recipeText {
                    Section {
                        Button {
                            Task { await ajouterAuxCourses() }
                        } label: {
                            Label("Ajouter à la liste de courses", systemImage: "cart.badge.plus")
                        }
                        .disabled(sending)
                    } footer: {
                        Text("Claude lira les produits sur la photo et les proposera dans la liste du bon magasin (une seule par magasin : supermarché, Leroy Merlin…), créée s'il le faut, à garder ou retirer dans l'app.")
                    }
                }

                if HAConfig.isActive, let fichier {
                    Section {
                        Toggle(isOn: $joindre) {
                            Label("Joindre « \(fichier.nom) »", systemImage: "paperclip")
                        }
                        if joindre {
                            Picker("Ajouter à", selection: $cible) {
                                Text("Cette nouvelle tâche").tag(String?.none)
                                ForEach(recentes, id: \.cle) { Text($0.titre).tag(Optional($0.cle)) }
                            }
                        }
                    } header: {
                        Text("Pièce jointe")
                    } footer: {
                        if joindre { Text("Rangée dans Home Assistant ; son texte est lu sur l'iPhone pour aider le tri.") }
                    }
                }

                Section {
                    Picker("Ranger dans", selection: $kind) {
                        Text("Tâche").tag(ToSee.Kind?.none)
                        ForEach(ToSee.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
                    }
                } footer: {
                    if kind != nil { Text("Gardé dans Envies, sans échéance ni relance.") }
                }

                if kind == nil {
                Section("Échéance") {
                    Picker("Jour", selection: dayChoice) {
                        Text("Aujourd'hui").tag(DayChoice.today)
                        Text("Demain").tag(DayChoice.tomorrow)
                        Text("Autre").tag(DayChoice.other)
                        Text("Sans date").tag(DayChoice.none)
                    }
                    .pickerStyle(.segmented)
                    if dayChoice.wrappedValue == .other {
                        DatePicker("Date", selection: Binding(get: { day ?? .now }, set: { day = Calendar.current.startOfDay(for: $0) }),
                                   in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    }
                    if day != nil {
                        Toggle("Heure", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                }

                Section("Priorité") {
                    Picker("Priorité", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(kind?.title ?? "Nouvelle tâche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .principal) {
                    ShareModePicker(mode: $mode)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Ajouter") { Task { await add() } }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private enum DayChoice: Hashable { case today, tomorrow, other, none }

    private var dayChoice: Binding<DayChoice> {
        Binding {
            let calendar = Calendar.current
            guard let day else { return .none }
            if calendar.isDateInToday(day) { return .today }
            if calendar.isDateInTomorrow(day) { return .tomorrow }
            return .other
        } set: { choice in
            let today = Calendar.current.startOfDay(for: .now)
            switch choice {
            case .today: day = today
            case .tomorrow: day = Calendar.current.date(byAdding: .day, value: 1, to: today)
            case .other: day = day ?? Calendar.current.date(byAdding: .day, value: 2, to: today)
            case .none: day = nil
            }
        }
    }

    private func load() {
        chargerPieceJointe()
        let draft = SharedMessage.draft(from: original)
        title = draft.title
        proposedTitle = draft.title
        day = draft.day
        priority = draft.priority
        body_ = draft.body
        if let m = draft.minutes {
            hasTime = true
            time = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now)!
        }
        // Une photo de recette (texte lu sur l'image) : une liste de courses, pas un spot photo.
        if let texte = photo?.texte, SharedRecipe.looksLikeRecipe(texte) {
            recipeText = true
            asList = true
            day = nil
            let premiere = texte.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count >= 3 && !SharedRecipe.looksLikeRecipe($0) }
            title = premiere.map { String($0.prefix(60)) } ?? "Recette"
            proposedTitle = title
            return
        }
        // Un rendez-vous (P9-L4) : capture d'un SMS ou d'un e-mail, carton photographié, message partagé.
        // Date, heure, adresse et téléphone lus sur l'appareil ; la capture est jointe (cochée d'office).
        if SharedLink.url(in: original) == nil || photo != nil,
           let rdv = SharedAppointment.detect(in: photo?.texte ?? original) {
            appointment = true
            kind = nil
            day = rdv.day
            if let m = rdv.minutes {
                hasTime = true
                time = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now)!
            }
            if photo != nil || title.isEmpty {
                title = rdv.title
                proposedTitle = title
            }
            if rdv.address != nil || rdv.phone != nil {
                place = SharedPlace(name: rdv.placeName ?? rdv.address ?? rdv.title, address: rdv.address,
                                    source: "saisie", phone: rdv.phone)
            }
            return
        }
        // Une photo : un spot photo, à l'endroit où elle a été prise.
        if let photo {
            kind = .photoSpot
            day = nil
            if let lat = photo.latitude, let lon = photo.longitude { locate(lat, lon, source: "photo") }
            return
        }
        // Des coordonnées (« 48.8215, 2.4123 », « 48°49'17"N 2°24'44"E ») : un point.
        if SharedLink.url(in: original) == nil, let (lat, lon) = SharedPlace.coordinates(inText: original) {
            locate(lat, lon, source: "gps")
            return
        }
        // Un lien (vidéo, album, article) : une envie, avec le titre de la page si on n'a partagé que le lien.
        guard let url = SharedLink.url(in: original) else {
            if SharedRecipe.looksLikeRecipe(original) {
                recipeText = true
                asList = true
                day = nil
            }
            return
        }
        // Une page de recette : les ingrédients sont lus en parallèle du titre.
        Task {
            guard let found = await SharedRecipe.fetch(url) else { return }
            recipe = found
            asList = true
            kind = nil
            day = nil
            if title == proposedTitle || title.isEmpty || fetchingTitle {
                title = found.titre
                proposedTitle = title
            }
        }
        let linkOnly = draft.body.trimmingCharacters(in: .whitespacesAndNewlines) == url.absoluteString
        // Un lieu (Plans, Google Maps) : nom et adresse lus dans le lien, jamais dans la page.
        if SharedPlace.isMapLink(url) {
            fetchingTitle = true
            Task {
                if let found = await SharedPlace.resolve(url) {
                    place = found
                    placeLink = url
                    if title == proposedTitle || linkOnly {
                        title = found.name
                        proposedTitle = title
                    }
                    fetchingTitle = false
                    // Puis la catégorie (bar, épicerie…) : le type est proposé tant qu'on ne l'a pas choisi.
                    let completed = await PlaceCategory.complete(found)
                    place = completed
                    if let envie = SharedPlace.envie(forCategory: completed.category) {
                        suggestion = envie
                        if kind == nil {
                            kind = envie.kind
                            day = nil
                        }
                    }
                }
                fetchingTitle = false
            }
            return
        }
        kind = SharedLink.kind(for: url, linkOnly: linkOnly)
        if kind != nil { day = nil }
        // Titre entre guillemets dans le message de l'app (Disney+) : plus sûr que la page.
        if kind != nil, let quoted = SharedLink.quotedTitle(in: original), title == proposedTitle {
            title = quoted
            proposedTitle = quoted
            return
        }
        guard linkOnly else { return }
        fetchingTitle = true
        Task {
            let pageTitle = await SharedLink.title(of: url) ?? SharedLink.titleInPath(of: url)
                // Page sans titre utile (Netflix) : la plateforme, à renommer.
                ?? SharedLink.platform(for: url).map { "À regarder sur " + SharedLink.platformName($0) }
            // Une recette a déjà donné son nom : il prime sur le titre de la page.
            if let pageTitle, title == proposedTitle, recipe == nil {
                title = String(pageTitle.prefix(SharedMessage.maxTitleLength * 2))
                proposedTitle = title
            }
            fetchingTitle = false
        }
    }

    /// Pièce jointe : cochée d'office pour un PDF ou une capture sans position (pas pour un spot photo ni une recette),
    /// et la liste des tâches récentes pour l'ajouter à l'une d'elles.
    private func chargerPieceJointe() {
        guard HAConfig.isActive, let fichier else { return }
        let estPhotoDeSpot = photo?.hasLocation == true
        let estRecette = photo?.texte.map(SharedRecipe.looksLikeRecipe) ?? false
        joindre = fichier.type.conforms(to: .pdf) || (!estPhotoDeSpot && !estRecette)
        if original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, fichier.type.conforms(to: .pdf) {
            title = (fichier.nom as NSString).deletingPathExtension
            proposedTitle = title
        }
        Task {
            guard let synchro = await HAConfig.makeSynchroniser(withFallback: false),
                  let tous = try? synchro.tous() else { return }
            recentes = tous.filter { UUID(uuidString: $0.cle) != nil }
                .compactMap { e -> (String, String, String)? in
                    guard let t = try? TacheHA(valeur: e.valeur), !t.fait, !t.titre.isEmpty else { return nil }
                    return (e.cle, t.titre, e.modifieLe)
                }
                .sorted { $0.2 > $1.2 }.prefix(20).map { (cle: $0.0, titre: $0.1) }
        }
    }

    /// Lieu d'un point (photo, coordonnées) : nom et adresse proposés par Plans, titre si on n'en a pas.
    private func locate(_ latitude: Double, _ longitude: Double, source: String) {
        place = SharedPlace(name: "Point sur la carte", latitude: latitude, longitude: longitude, source: source)
        fetchingTitle = true
        Task {
            let found = await PlaceCategory.describe(latitude: latitude, longitude: longitude)
            let name = found.name ?? found.address ?? "Point sur la carte"
            place = SharedPlace(name: name, address: found.address, latitude: latitude, longitude: longitude, source: source)
            if title == proposedTitle {
                title = name
                proposedTitle = title
            }
            fetchingTitle = false
        }
    }

    /// Dans Home Assistant si l'app y range ses tâches, sinon directement chez Google (la vigie réveille
    /// ensuite l'iPhone) ; sans réponse de Google, file d'attente pour l'app.
    private func add() async {
        sending = true
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minutes = day != nil && hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : nil
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Une photo seule n'a pas de message : pas de ligne 📩 (la routine chercherait un titre dans le vide).
        var notes = original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : SharedMessage.notes(original: original, titleEdited: cleanTitle != proposedTitle)
        if !appointment, let dateLine = photo?.dateLine {
            notes = notes.isEmpty ? dateLine : notes + "\n" + dateLine
        }
        if let place {
            notes = TaskContact.notes(notes, setting: place.contact(link: placeLink))
        }
        if let kind {
            notes = ToSee.notes(notes, setting: ToSee(kind, note: suggestion?.kind == kind ? suggestion?.label : nil))
            day = nil
        }
        if asList, kind == nil {
            notes = notes.isEmpty ? "🍳 Recette : \(recipe?.titre ?? cleanTitle)" : notes + "\n🍳 Recette : \(recipe?.titre ?? cleanTitle)"
        }
        // Pièce jointe à une tâche existante : seule la pièce est ajoutée, pas de nouvelle tâche.
        if HAConfig.isActive, joindre, let cible, let piece = preparerPiece() {
            if await joindreA(cible, piece) { return onDone() }
        }
        if HAConfig.isActive, await addToHA(title: cleanTitle, notes: notes, minutes: minutes) {
            return onDone()
        }
        let fields: [String: Any] = [
            "title": cleanTitle,
            "notes": NotesTimeCodec.encode(minutes: minutes, priority: priority, notes: notes),
            "due": TasksAPI.due(fromDay: day) ?? NSNull(),
        ]
        let session = GoogleRefreshSession.shared
        let sent: Bool
        if session.isAvailable {
            let api = TasksAPI(token: { try await session.validAccessToken() })
            sent = await Self.within(seconds: 8) {
                await Journal.essayer(.reseau, "Envoi du partage à Google Tasks", { try await api.insert(fields) }) != nil
            }
        } else {
            sent = false
        }
        if !sent {
            PendingShares.add(.init(title: cleanTitle, notes: notes, day: day, minutes: minutes, priority: priority))
        }
        onDone()
    }

    /// Écrite dans la base locale partagée avec l'app (App Group) : elle part vers HA tout de suite si
    /// possible, sinon à la prochaine synchro de l'app (qui dépose aussi la copie iCloud). `false` si HA
    /// n'est pas réglé ou si la base est inaccessible.
    private func addToHA(title: String, notes: String, minutes: Int?) async -> Bool {
        guard let synchro = await HAConfig.makeSynchroniser(withFallback: false) else { return false }
        var tache = TacheHA(titre: title)
        tache.notes = notes
        tache.jour = TacheHA.jour(day)
        tache.heure = day == nil ? nil : TacheHA.heure(minutes)
        tache.priorite = priority == .normal ? nil : priority.rawValue
        if let place { tache.lieu = place.lieu(link: placeLink) }
        if joindre, cible == nil, let piece = preparerPiece() {
            tache.pieces = [piece]
            tache.notes = TacheHA.Piece.notes(tache.notes, setting: tache.pieces)
        }
        if asList, kind == nil {
            var liste = TacheHA.Liste(parts: recipe?.parts)
            let entree = recipe.map { $0.entree(lien: SharedLink.url(in: original)) }
                ?? SharedRecipe.entree(texte: photo?.texte ?? original, titre: title)
            liste.autres["recettes"] = .liste([entree])
            tache.liste = liste
        }
        guard let valeur = try? tache.valeur(),
              Journal.essayer(.synchro, "Écriture du partage", { try synchro.ecrire(UUID().uuidString.lowercased(), valeur) }) != nil
        else { return false }
        _ = await Self.within(seconds: 8) { @MainActor in
            await synchro.synchroniser()
            await PiecesJointes.envoyerEnAttente()
            return true
        }
        return true
    }

    /// Photo de produits (P9-R) : jointe à la liste d'achats ouverte la plus récente (ou à une nouvelle « Courses ») et
    /// notée à lire ; la vigie de Home Assistant propose les articles lus. Rien d'autre n'est créé.
    private func ajouterAuxCourses() async {
        guard let synchro = await HAConfig.makeSynchroniser(withFallback: false), let piece = preparerPiece() else { return }
        sending = true
        let maintenant = TacheHA.timestamp(.now)
        let ouvertes = ((try? synchro.tous()) ?? [])
            .filter { UUID(uuidString: $0.cle) != nil }
            .compactMap { e -> (cle: String, tache: TacheHA, modifie: String)? in
                guard let t = try? TacheHA(valeur: e.valeur), !t.fait, t.categorie == "Achats", t.liste != nil else { return nil }
                return (e.cle, t, e.modifieLe)
            }
            .sorted { $0.modifie > $1.modifie }
        let cle = ouvertes.first?.cle ?? UUID().uuidString.lowercased()
        var tache = ouvertes.first?.tache ?? {
            var t = TacheHA(titre: "Courses")
            t.categorie = "Achats"
            t.liste = TacheHA.Liste()
            return t
        }()
        if !tache.pieces.contains(where: { $0.id == piece.id }) && tache.pieces.count < TacheHA.Piece.maxParTache {
            tache.pieces.append(piece)
        }
        tache.notes = TacheHA.Piece.notes(tache.notes, setting: tache.pieces)
        var liste = tache.liste ?? TacheHA.Liste()
        liste.ajouterPhoto(piece: piece.id, le: maintenant, origine: "partage")
        tache.liste = liste
        guard let valeur = try? tache.valeur(),
              Journal.essayer(.synchro, "Photo vers la liste de courses", { try synchro.ecrire(cle, valeur) }) != nil
        else { sending = false; return }
        _ = await Self.within(seconds: 8) { @MainActor in
            await synchro.synchroniser()
            await PiecesJointes.envoyerEnAttente()
            return true
        }
        onDone()
    }

    /// La pièce prête (photo réduite, texte lu, mise en file d'envoi) ; `nil` si le fichier est illisible.
    private func preparerPiece() -> TacheHA.Piece? {
        guard let fichier else { return nil }
        return try? PiecesJointes.preparer(fichier.donnees, nom: fichier.nom, type: fichier.type, source: "partage")
    }

    /// Ajoute la pièce à une tâche existante (5 au plus) ; `false` si la tâche n'est plus lisible.
    private func joindreA(_ cle: String, _ piece: TacheHA.Piece) async -> Bool {
        guard let synchro = await HAConfig.makeSynchroniser(withFallback: false),
              let valeur = try? synchro.valeur(cle), var tache = try? TacheHA(valeur: valeur) else { return false }
        if !tache.pieces.contains(where: { $0.id == piece.id }) && tache.pieces.count < TacheHA.Piece.maxParTache {
            tache.pieces.append(piece)
        }
        tache.notes = TacheHA.Piece.notes(tache.notes, setting: tache.pieces)
        guard let nouvelle = try? tache.valeur(),
              Journal.essayer(.synchro, "Ajout de la pièce jointe", { try synchro.ecrire(cle, nouvelle) }) != nil
        else { return false }
        _ = await Self.within(seconds: 8) { @MainActor in
            await synchro.synchroniser()
            await PiecesJointes.envoyerEnAttente()
            return true
        }
        return true
    }

    /// Une feuille de partage ne doit pas rester bloquée : sans réponse de Google, on passe par la file d'attente.
    private static func within(seconds: Double, _ operation: @escaping @Sendable () async -> Bool) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await operation() }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}

private extension String {
    /// « bar » → « Bar ».
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
