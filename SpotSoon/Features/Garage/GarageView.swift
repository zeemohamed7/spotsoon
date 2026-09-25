import SwiftUI

struct GarageView: View {
    let store: VehicleStore
    @State private var editingVehicle: Vehicle?
    @State private var showingAddVehicle = false
    @State private var vehicleToDelete: Vehicle?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let current = store.currentVehicle {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.spotPurple)
                        Text("Active vehicle set to \(current.nickname)")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.spotInk)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.spotLavender, in: RoundedRectangle(cornerRadius: 13))
                }

                Text("Your selected vehicle helps the other driver recognize you during an active curb handover.")
                    .font(.footnote).foregroundStyle(.secondary)

                if store.isLoading && store.vehicles.isEmpty {
                    ProgressView("Loading garage…")
                        .frame(maxWidth: .infinity).padding(.vertical, 50)
                } else if store.vehicles.isEmpty && store.errorMessage == nil {
                    emptyState
                } else {
                    HStack {
                        Text("SAVED VEHICLES (\(store.vehicles.count))")
                        Spacer()
                        Label("Tap to switch", systemImage: "arrow.left.arrow.right")
                    }
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        ForEach(store.vehicles) { vehicleCard($0) }
                    }
                }

                if let error = store.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("Retry") { Task { await store.load() } }.font(.footnote.weight(.semibold))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                }

                Button { showingAddVehicle = true } label: {
                    Label("Add Another Vehicle", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.background, in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Color.spotPurple.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.spotPurple)

                Label {
                    Text("Privacy First: SpotSoon only reveals vehicle details to the other participant during an active handover.")
                } icon: {
                    Image(systemName: "shield.fill").foregroundStyle(.blue)
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 5)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("My Garage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { showingAddVehicle = true }
            }
        }
        .task { if store.vehicles.isEmpty { await store.load() } }
        .refreshable { await store.load() }
        .sheet(isPresented: $showingAddVehicle) { VehicleEditorView(store: store) }
        .sheet(item: $editingVehicle) { VehicleEditorView(store: store, vehicle: $0) }
        .confirmationDialog(
            "Delete \(vehicleToDelete?.nickname ?? "vehicle")?",
            isPresented: Binding(get: { vehicleToDelete != nil }, set: { if !$0 { vehicleToDelete = nil } }),
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
            Text("Active handovers keep their existing vehicle snapshot. If this is Today’s Vehicle, the most recently updated remaining vehicle becomes current.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.side").font(.system(size: 36)).foregroundStyle(Color.spotPurple)
            Text("Your garage is empty").font(.headline)
            Text("Add a vehicle to publish or claim a parking signal.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func vehicleCard(_ vehicle: Vehicle) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Button {
                    guard !vehicle.isCurrent else { return }
                    Task { await store.select(vehicle) }
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                    Image(systemName: vehicle.isCurrent ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(vehicle.isCurrent ? Color.spotPurple : Color.secondary.opacity(0.35))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(vehicle.nickname).font(.headline).foregroundStyle(Color.spotInk)
                            if vehicle.isCurrent {
                                Text("Today’s Vehicle")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(Color.spotPurple)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.spotLavender, in: Capsule())
                            }
                        }
                        Text(primaryDescription(vehicle)).font(.caption).foregroundStyle(.secondary)
                    }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button("Edit", systemImage: "pencil") { editingVehicle = vehicle }
                    if !vehicle.isCurrent {
                        Button("Use as Today’s Vehicle", systemImage: "checkmark.circle") {
                            Task { await store.select(vehicle) }
                        }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { vehicleToDelete = vehicle }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 30, height: 30)
                }
                .accessibilityLabel("Vehicle actions")
            }

            Divider()

            HStack {
                Label(vehicle.plateSuffix.map { "Plate ending ••• \($0)" } ?? "No plate suffix", systemImage: "rectangle.and.pencil.and.ellipsis")
                Spacer()
                Circle().fill(swatchColor(vehicle.color)).frame(width: 9, height: 9)
                Text(vehicle.color)
            }
            .font(.caption).foregroundStyle(.secondary)

            if store.isWorking(on: vehicle.id) { ProgressView().controlSize(.small) }
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(vehicle.isCurrent ? Color.spotPurple.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: vehicle.isCurrent ? 1.5 : 1)
        }
        .disabled(store.isWorking(on: vehicle.id))
    }

    private func primaryDescription(_ vehicle: Vehicle) -> String {
        let appearance = "\(vehicle.color) \(vehicle.vehicleType.title)"
        let identity = [vehicle.make, vehicle.model]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return identity.isEmpty ? appearance : "\(appearance) · \(identity)"
    }

    private func swatchColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "white": .white
        case "silver": Color(white: 0.78)
        case "grey", "gray", "midnight grey", "midnight gray": Color(white: 0.38)
        case "black": .black
        case "blue": .blue
        case "red": .red
        case "orange": .orange
        default: .secondary
        }
    }
}
