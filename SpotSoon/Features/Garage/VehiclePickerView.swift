import SwiftUI

struct VehiclePickerView: View {
    let title: String
    let store: VehicleStore
    @Binding var selectedVehicleID: UUID?
    @State private var showingAddVehicle = false

    private var selectedVehicle: Vehicle? {
        store.vehicles.first { $0.id == selectedVehicleID }
    }

    var body: some View {
        Section(title) {
            if let selectedVehicle {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedVehicle.nickname).font(.headline)
                    Text(selectedVehicle.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                Menu("Change") {
                    ForEach(store.vehicles) { vehicle in
                        Button {
                            selectedVehicleID = vehicle.id
                        } label: {
                            if vehicle.id == selectedVehicleID {
                                Label(vehicle.nickname, systemImage: "checkmark")
                            } else {
                                Text(vehicle.nickname)
                            }
                        }
                    }
                    Divider()
                    Button("Add Vehicle", systemImage: "plus") { showingAddVehicle = true }
                }
            } else if store.isLoading {
                ProgressView("Loading vehicles…")
            } else {
                Text("Add a vehicle before continuing.").foregroundStyle(.secondary)
                Button("Add Vehicle", systemImage: "plus") { showingAddVehicle = true }
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .task {
            if store.vehicles.isEmpty && !store.isLoading { await store.load() }
            selectDefaultIfNeeded()
        }
        .onChange(of: store.vehicles) { _, _ in selectDefaultIfNeeded() }
        .sheet(isPresented: $showingAddVehicle) {
            VehicleEditorView(store: store) { vehicle in selectedVehicleID = vehicle.id }
        }
    }

    private func selectDefaultIfNeeded() {
        guard selectedVehicle == nil else { return }
        selectedVehicleID = store.currentVehicle?.id ?? store.vehicles.first?.id
    }
}
