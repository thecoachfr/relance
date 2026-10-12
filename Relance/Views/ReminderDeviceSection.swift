import SwiftUI
import UserNotifications

/// « Appareil qui relance » : un seul choix, le même sur l'iPhone, l'iPad et le Mac (iCloud).
struct ReminderDeviceSection: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var chosen = ReminderDevice.chosen
    @State private var notificationStatus: UNAuthorizationStatus?

    private var here: ReminderDevice { ReminderDevice.current }

    var body: some View {
        Section {
            Picker("Appareil qui relance", selection: $chosen) {
                ForEach(ReminderDevice.allCases) { device in
                    Label(device == here ? "\(device.name) (cet appareil)" : device.name, systemImage: device.symbol)
                        .tag(device)
                }
            }
            .onChange(of: chosen) { _, device in
                guard device != ReminderDevice.chosen else { return }
                ReminderDevice.chosen = device
                Task {
                    if device == here { _ = await store.scheduler.requestAuthorization() }
                    notificationStatus = await store.scheduler.authorizationStatus()
                    await store.reschedule()
                }
            }
            if chosen == here, notificationStatus == .denied {
                Button("Notifications refusées : ouvrir les réglages") { openURL(Self.notificationSettingsURL) }
            }
        } header: {
            Text("Relances")
        } footer: {
            Text(footer)
        }
        // Choix changé sur un autre appareil pendant que l'écran est ouvert.
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            chosen = ReminderDevice.chosen
        }
        .task { notificationStatus = await store.scheduler.authorizationStatus() }
    }

    private var footer: String {
        let who = chosen == here ? "Cet appareil relance" : "Les relances sont sur ton \(chosen.name)"
        return who + ". Un seul appareil à la fois, pour ne pas sonner deux fois ; ce choix est le même partout. L'appareil d'avant s'arrête à sa prochaine ouverture."
    }

    private static var notificationSettingsURL: URL {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        #else
        URL(string: UIApplication.openNotificationSettingsURLString)!
        #endif
    }
}
