import SwiftUI

struct SettingsView: View {
    let vehicleStore: VehicleStore

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
                    Text("Coming later").foregroundStyle(.secondary)
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
        .task { if vehicleStore.vehicles.isEmpty { await vehicleStore.load() } }
    }
}
