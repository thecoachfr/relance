import SwiftUI

/// Tags en texte gris, sans pastille : on ne les confond pas avec la catégorie (seule à avoir une pastille).
struct TagsText: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            Text(tags.map { "#" + $0 }.joined(separator: " "))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Tags : " + tags.joined(separator: ", "))
        }
    }
}

/// Ligne « Tags » des formulaires : « Aucun » ou « #SCI #Photo ».
struct TagsRow: View {
    @Binding var tags: [String]

    var body: some View {
        NavigationLink {
            TagsPickerView(tags: $tags)
        } label: {
            LabeledContent("Tags", value: tags.isEmpty ? "Aucun" : tags.map { "#" + $0 }.joined(separator: " "))
        }
    }
}

/// Choix des tags d'une tâche : ceux connus (cochés ou non), puis un champ pour en créer un.
struct TagsPickerView: View {
    @Environment(TaskStore.self) private var store
    @Binding var tags: [String]
    @State private var newTag = ""
    @State private var created: [String] = []

    private var known: [String] {
        let all = store.knownTags() + created
        var seen = Set<String>()
        return (all + tags).filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        Form {
            Section {
                ForEach(known, id: \.self) { tag in
                    let on = tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                    Button {
                        toggle(tag, on: on)
                    } label: {
                        HStack {
                            Text("#" + tag).foregroundStyle(.primary)
                            Spacer()
                            if on { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .disabled(!on && tags.count >= TaskTag.maxPerTask)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            } footer: {
                Text("Jusqu'à \(TaskTag.maxPerTask) tags par tâche, pour la retrouver par projet ou par contexte.")
            }

            Section("Nouveau tag") {
                TextField("Ex. Vacances", text: $newTag)
                    .submitLabel(.done)
                    .onSubmit(create)
            }
        }
        .navigationTitle("Tags")
        .inlineNavigationTitle()
    }

    private func toggle(_ tag: String, on: Bool) {
        if on {
            tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        } else if tags.count < TaskTag.maxPerTask {
            tags.append(tag)
        }
    }

    private func create() {
        guard let tag = TaskTag.normalized([newTag]).first else { return }
        if !known.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { created.append(tag) }
        toggle(tag, on: false)
        newTag = ""
    }
}
