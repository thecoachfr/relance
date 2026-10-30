import EventKit
import SwiftUI

/// Vue Agenda d'À faire (30/10/2026, maquette validée par Alexandre) : une journée en ligne du temps. Bande de la
/// semaine en tête ; « Pour info », « En retard » (aujourd'hui) et « Toute la journée » au-dessus ; les tâches avec
/// une heure en blocs (leur durée, sinon 1 h) ; l'agenda iOS en gris derrière, s'il est autorisé. Toucher une tâche
/// ouvre sa fiche, le rond la coche, toucher une plage vide ouvre la saisie à cette heure. Pas encore de
/// glisser-déposer ni de vue semaine (à voir, choix d'Alexandre).
struct AgendaView: View {
    /// Tâches actives datées (la requête d'À faire).
    let taches: [TaskItem]
    let now: Date
    var onOpen: (TaskItem) -> Void
    var onDone: (TaskItem) -> Void
    var onAdd: (Date, Int?) -> Void

    @State private var jour = Calendar.current.startOfDay(for: .now)
    @State private var evenements: [EKEvent] = []
    @State private var agendaAutorise = CalendarLink.shared.isAuthorized

    static let hauteurHeure: CGFloat = 56
    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 0) {
            bandeSemaine
            Divider()
            // En-tête fixe (le jour, Pour info, En retard, Toute la journée) : seule la ligne du temps défile.
            VStack(alignment: .leading, spacing: 8) { enTete }
                .padding(.horizontal)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ScrollViewReader { defilement in
                ScrollView {
                    grille
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                }
                .onAppear { defilement.scrollTo(heureDeDepart, anchor: .top) }
                .onChange(of: jour) { defilement.scrollTo(heureDeDepart, anchor: .top) }
            }
        }
        .task(id: jour) { charger() }
    }

    // MARK: - Semaine

    private var semaine: [Date] {
        let lundi = calendar.dateInterval(of: .weekOfYear, for: jour)?.start ?? jour
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: lundi) }
    }

    private var bandeSemaine: some View {
        HStack(spacing: 0) {
            Button { deplacer(-7) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless).accessibilityLabel("Semaine précédente")
            ForEach(semaine, id: \.self) { d in
                let choisi = calendar.isDate(d, inSameDayAs: jour)
                Button { jour = d } label: {
                    VStack(spacing: 3) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                        Text(d.formatted(.dateTime.day()))
                            .font(.callout.weight(choisi ? .bold : .regular))
                            .foregroundStyle(choisi ? Color.white : calendar.isDateInToday(d) ? Color.accentColor : .primary)
                            .frame(width: 30, height: 30)
                            .background(choisi ? Color.accentColor : .clear, in: .circle)
                        Circle().fill(nombre(d) > 0 ? Color.secondary : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day().month(.wide)) + ", \(nombre(d)) tâche(s)")
            }
            Button { deplacer(7) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless).accessibilityLabel("Semaine suivante")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func deplacer(_ jours: Int) {
        jour = calendar.date(byAdding: .day, value: jours, to: jour) ?? jour
    }

    private func nombre(_ d: Date) -> Int {
        taches.filter { $0.dueDay.map { calendar.isDate($0, inSameDayAs: d) } ?? false }.count
    }

    // MARK: - En-tête du jour

    private var duJour: [TaskItem] {
        taches.filter { t in !t.estPourInfo && t.dueDay.map { calendar.isDate($0, inSameDayAs: jour) } ?? false }
    }

    @ViewBuilder private var enTete: some View {
        HStack {
            Text(jour.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.title3.bold())
            Spacer()
            if !calendar.isDateInToday(jour) {
                Button("Aujourd'hui") { jour = calendar.startOfDay(for: .now) }.font(.callout)
            }
        }
        .padding(.top, 8)
        let infos = taches.filter { $0.estPourInfo && $0.pourInfoDuJour(now: jour) }
        if !infos.isEmpty {
            Label(infos.map { $0.title + ($0.heurePourInfo.map { " · " + $0 } ?? "") }.joined(separator: " · "),
                  systemImage: "megaphone")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        if calendar.isDateInToday(jour) {
            let retard = taches.filter { $0.isOverdue(now: now) && !calendar.isDate($0.dueDay ?? .distantPast, inSameDayAs: jour) }
            ligneDeTaches("En retard", retard, couleur: .red)
        }
        let sansHeure = duJour.filter { $0.dueMinutes == nil }
        let evenementsJournee = evenements.filter(\.isAllDay)
        if !sansHeure.isEmpty || !evenementsJournee.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Toute la journée").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(sansHeure) { puce($0) }
                ForEach(evenementsJournee, id: \.eventIdentifier) { e in
                    Label(e.title ?? "Événement", systemImage: "calendar").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        if !agendaAutorise {
            Button("Afficher mon agenda iOS", systemImage: "calendar.badge.plus") {
                Task {
                    agendaAutorise = await CalendarLink.shared.requestAccess()
                    charger()
                }
            }
            .font(.footnote)
        }
    }

    @ViewBuilder private func ligneDeTaches(_ titre: String, _ liste: [TaskItem], couleur: Color) -> some View {
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(titre).font(.caption.bold()).foregroundStyle(couleur)
                ForEach(liste) { puce($0) }
            }
        }
    }

    private func puce(_ t: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button { onDone(t) } label: {
                Image(systemName: t.priority == .urgent || t.isOverdue(now: now) ? "circle.circle" : "circle")
                    .foregroundStyle(t.priority == .urgent || t.isOverdue(now: now) ? Color.red : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Marquer « \(t.title) » comme faite")
            Button { onOpen(t) } label: {
                Text(t.title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Ligne du temps

    private var heureDeDepart: Int {
        let premiere = (duJour.compactMap(\.dueMinutes) + evenements.filter { !$0.isAllDay }.map { minutes($0.startDate) }).min()
        if calendar.isDateInToday(jour) { return max(0, min(calendar.component(.hour, from: now) - 1, (premiere ?? 24 * 60) / 60)) }
        return max(0, ((premiere ?? 8 * 60) / 60) - 1)
    }

    private func minutes(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Un bloc de la grille : une tâche ou un événement, placé en minutes, avec sa colonne en cas de chevauchement.
    private struct Bloc: Identifiable {
        let id: String
        let debut: Int
        let fin: Int
        let tache: TaskItem?
        let titre: String
        let sousTitre: String?
        var colonne = 0
        var colonnes = 1
    }

    private var blocs: [Bloc] {
        // Une tâche déjà ajoutée à l'agenda n'apparaît qu'une fois (son événement est retiré).
        let lies = Set(duJour.compactMap(\.calendarEventID))
        var liste = duJour.filter { $0.dueMinutes != nil }.map { t -> Bloc in
            let debut = t.dueMinutes!
            return Bloc(id: t.localID.uuidString, debut: debut, fin: min(24 * 60, debut + max(30, t.dureeMinutes ?? 60)),
                        tache: t, titre: t.title, sousTitre: TaskContact(notes: t.notes)?.name)
        }
        for e in evenements where !e.isAllDay && !lies.contains(e.eventIdentifier ?? "") {
            let debut = calendar.isDate(e.startDate, inSameDayAs: jour) ? minutes(e.startDate) : 0
            let fin = calendar.isDate(e.endDate, inSameDayAs: jour) ? minutes(e.endDate) : 24 * 60
            // Même titre et même heure qu'une tâche : l'événement d'une tâche ajoutée depuis un autre appareil.
            guard !liste.contains(where: { $0.titre == e.title && $0.debut == debut }) else { continue }
            liste.append(Bloc(id: "ek-" + (e.eventIdentifier ?? UUID().uuidString), debut: debut, fin: max(fin, debut + 30),
                              tache: nil, titre: e.title ?? "Événement", sousTitre: e.calendar?.title))
        }
        liste.sort { ($0.debut, $0.fin) < ($1.debut, $1.fin) }
        // Colonnes : groupes de blocs qui se chevauchent, chaque bloc dans la première colonne libre.
        var groupe: [Int] = []
        var finGroupe = -1
        func fermer() {
            let n = (groupe.map { liste[$0].colonne }.max() ?? 0) + 1
            for i in groupe { liste[i].colonnes = n }
            groupe = []
        }
        for i in liste.indices {
            if liste[i].debut >= finGroupe { fermer() }
            let prises = Set(groupe.filter { liste[$0].fin > liste[i].debut }.map { liste[$0].colonne })
            liste[i].colonne = (0...).first { !prises.contains($0) }!
            groupe.append(i)
            finGroupe = max(finGroupe, liste[i].fin)
        }
        fermer()
        return liste
    }

    private var grille: some View {
        let h = Self.hauteurHeure
        // Les heures en pile (mise en page réelle : `scrollTo` s'y fie), les blocs par-dessus.
        return VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { heure in
                HStack(alignment: .top, spacing: 4) {
                    Text("\(heure) h").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                        .offset(y: -6)
                    VStack(spacing: 0) {
                        Divider()
                        // Plage vide : la toucher ouvre la saisie à cette heure.
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { onAdd(jour, heure * 60) }
                            .accessibilityLabel("Ajouter une tâche à \(heure) h")
                    }
                }
                .frame(height: h)
                .id(heure)
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                let largeur = geo.size.width - 44
                ZStack(alignment: .topLeading) {
                    ForEach(blocs) { b in
                        let largeurBloc = largeur / CGFloat(b.colonnes)
                        blocVue(b)
                            .frame(width: largeurBloc - 2, height: max(28, CGFloat(b.fin - b.debut) / 60 * h - 2))
                            .offset(x: 44 + CGFloat(b.colonne) * largeurBloc, y: CGFloat(b.debut) / 60 * h + 1)
                    }
                    if calendar.isDateInToday(jour) {
                        HStack(spacing: 0) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Rectangle().fill(.red).frame(height: 1.5)
                        }
                        .frame(width: largeur + 8)
                        .offset(x: 40, y: CGFloat(minutes(now)) / 60 * h - 4)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Maintenant")
                    }
                }
            }
        }
    }

    @ViewBuilder private func blocVue(_ b: Bloc) -> some View {
        if let t = b.tache {
            let rouge = t.priority == .urgent || t.isOverdue(now: now)
            HStack(alignment: .top, spacing: 6) {
                Button { onDone(t) } label: {
                    Image(systemName: "circle").foregroundStyle(rouge ? Color.red : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Marquer « \(t.title) » comme faite")
                VStack(alignment: .leading, spacing: 1) {
                    Text(b.titre).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let s = b.sousTitre { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background((rouge ? Color.red : Color.accentColor).opacity(0.15), in: .rect(cornerRadius: 8))
            .overlay(alignment: .leading) {
                Rectangle().fill(rouge ? Color.red : Color.accentColor).frame(width: 3)
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { onOpen(t) }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(b.titre).font(.caption.weight(.semibold)).lineLimit(2)
                if let s = b.sousTitre { Text(s).font(.caption2).lineLimit(1) }
            }
            .foregroundStyle(.secondary)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
            .accessibilityLabel("Agenda : \(b.titre)")
        }
    }

    private func charger() {
        agendaAutorise = CalendarLink.shared.isAuthorized
        evenements = CalendarLink.shared.evenements(du: jour)
    }
}
