import SwiftUI

struct SettingsView: View {
    let vehicleStore: VehicleStore
    let locationStore: LocationStore

    var body: some View {
        List {
            Section("Account") {
                Label("Anonymous account active", systemImage: "person.crop.circle.badge.checkmark")
                Text("Your saved garage is private to this anonymous Supabase account.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Parking") {
                NavigationLink {
                    GarageView(store: vehicleStore)
                } label: {
                    Label("My Garage", systemImage: "car.2")
                }
                LabeledContent("Today’s Vehicle") {
                    Text(vehicleStore.currentVehicle?.nickname ?? "None")
                }
                LabeledContent("Location Access") {
                    Text(locationStore.authorizationState.title)
                        .foregroundStyle(locationStore.authorizationState == .authorized ? .primary : .secondary)
                }
                Text("Location is requested only to verify that you are at the selected parking area when publishing. SpotSoon does not track you in the background.")
                    .font(.footnote).foregroundStyle(.secondary)
                if locationStore.authorizationState == .denied {
                    Button("Open Location Settings", systemImage: "gear") {
                        locationStore.openSettings()
                    }
                }
            }

            Section("Privacy & Safety") {
                Text("Only the signal creator and current claimant can view handover passes and vehicle snapshots.")
                Text("Visually verify only when safely stopped. Do not block traffic or confront another driver.")
            }

            Section("About SpotSoon") {
                Text("SpotSoon coordinates short-lived campus parking handovers.")
            }
        }
        .navigationTitle("Settings")
        .task {
            locationStore.refreshAuthorizationState()
            if vehicleStore.vehicles.isEmpty { await vehicleStore.load() }
        }
    }
}
