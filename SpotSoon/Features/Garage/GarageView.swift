import SwiftUI

struct GarageView: View {
    let store: VehicleStore
    @State private var editingVehicle: Vehicle?
    @State private var showingAddVehicle = false
    @State private var vehicleToDelete: Vehicle?

    var body: some View {
        List {
            if store.isLoading && store.vehicles.isEmpty {
                ProgressView("Loading garage…")
            } else if store.vehicles.isEmpty && store.errorMessage == nil {
                ContentUnavailableView(
                    "Your garage is empty",
                    systemImage: "car.side",
                    description: Text("Add a vehicle to publish or claim a parking signal.")
                )
            }

            if let error = store.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { Task { await store.load() } }
                }
            }

            ForEach(store.vehicles) { vehicle in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(vehicle.nickname).font(.headline)
                        Spacer()
                        if vehicle.isCurrent {
                            Text("Today’s Vehicle")
                                .font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(vehicle.summary).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if !vehicle.isCurrent {
                            Button("Use Today", systemImage: "checkmark.circle") {
                                Task { await store.select(vehicle) }
                            }
                        }
                        Button("Edit", systemImage: "pencil") { editingVehicle = vehicle }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            vehicleToDelete = vehicle
                        }
                        .accessibilityIdentifier("delete-vehicle-\(vehicle.id.uuidString)")
                    }
                    // Separate hit regions for multiple buttons inside a List row.
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    if store.isWorking(on: vehicle.id) { ProgressView() }
                }
                .disabled(store.isWorking(on: vehicle.id))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        vehicleToDelete = vehicle
                    }
                }
            }
        }
        .navigationTitle("My Garage")
        .toolbar { Button("Add Vehicle", systemImage: "plus") { showingAddVehicle = true } }
        .task { if store.vehicles.isEmpty { await store.load() } }
        .refreshable { await store.load() }
        .sheet(isPresented: $showingAddVehicle) { VehicleEditorView(store: store) }
        .sheet(item: $editingVehicle) { VehicleEditorView(store: store, vehicle: $0) }
        .confirmationDialog(
            "Delete \(vehicleToDelete?.nickname ?? "vehicle")?",
            isPresented: Binding(
                get: { vehicleToDelete != nil },
                set: { if !$0 { vehicleToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let vehicleToDelete {
                Button("Delete Vehicle", role: .destructive) {
                    let vehicle = vehicleToDelete
                    self.vehicleToDelete = nil
                    Task { await store.delete(vehicle) }
                }
            }
            Button("Cancel", role: .cancel) { vehicleToDelete = nil }
        } message: {
            Text("Active handovers keep their existing vehicle snapshot.")
        }
    }
}
