import SwiftUI

/// Premier lancement : la connexion au compte Google, rien d'autre (les relances restent sur l'iPhone).
struct MacSignInView: View {
    @Environment(GoogleAuth.self) private var auth
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Tes tâches Google, sur le Mac").font(.title.bold())
                Text("Aiguillage lit la liste « Mes tâches », où arrivent les rappels dictés à Google Home.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Se connecter avec Google") {
                Task {
                    working = true
                    defer { working = false }
                    do { try await auth.signIn() } catch { self.error = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working)
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: 480)
    }
}
