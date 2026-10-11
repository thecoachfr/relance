import SwiftUI

/// Deux étapes : se connecter à Google, puis autoriser les notifications en sachant pourquoi.
struct OnboardingView: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(TaskStore.self) private var store
    @Binding var done: Bool
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: auth.isSignedIn ? "bell.badge" : "checklist")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            if auth.isSignedIn {
                step(title: "Des relances jusqu'à ce que ce soit fait",
                     text: "Relance te prévient à l'heure prévue, une heure après, puis le soir à 20 h tant que la tâche n'est pas cochée. Rien à programmer.")
                Button("Autoriser les notifications") {
                    Task {
                        _ = await store.scheduler.requestAuthorization()
                        await store.sync()
                        done = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                step(title: "Tes tâches Google, avec des relances qui insistent",
                     text: "Relance lit la liste « Mes tâches », où arrivent les rappels dictés à Google Home.")
                Button("Se connecter avec Google") {
                    Task {
                        do { try await auth.signIn() } catch { self.error = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 520)
    }

    private func step(title: String, text: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}
