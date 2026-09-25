import SwiftUI

struct CreateSignalView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SignalStore
    let vehicleStore: VehicleStore
    @State private var campus = ParkingSignal.Campus.campusA
    @State private var zone = "A1"
    @State private var minutes = 5
    @State private var selectedVehicleID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Campus", selection: $campus) {
                    ForEach(ParkingSignal.Campus.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: campus) { _, value in zone = value.zones[0] }
                Picker("Zone", selection: $zone) {
                    ForEach(campus.zones, id: \.self) { Text($0).tag($0) }
                }
                Picker("Leaving in", selection: $minutes) {
                    ForEach([2, 5, 10], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                VehiclePickerView(
                    title: "Vehicle you’re leaving in",
                    store: vehicleStore,
                    selectedVehicleID: $selectedVehicleID
                )
                Section {
                    Button("Publish") {
                        Task {
                            if await store.publish(
                                campus: campus,
                                zone: zone,
                                minutes: minutes,
                                ownerVehicleID: selectedVehicleID
                            ) { dismiss() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isPublishing)
                }
                if let error = store.publishError { Text(error).foregroundStyle(.red) }
                if store.isPublishing { ProgressView("Publishing…") }
            }
            .disabled(store.isPublishing)
            .navigationTitle("Leaving signal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") {
                        Task {
                            if await store.publish(
                                campus: campus,
                                zone: zone,
                                minutes: minutes,
                                ownerVehicleID: selectedVehicleID
                            ) { dismiss() }
                        }
                    }.disabled(store.isPublishing)
                }
            }
            .interactiveDismissDisabled(store.isPublishing)
        }
    }
}
