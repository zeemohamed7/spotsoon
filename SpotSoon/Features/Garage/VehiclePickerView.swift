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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.vehicles.isEmpty {
                    Menu("Change Vehicle") {
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spotPurple)
                }
            }

            if let selectedVehicle {
                HStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .foregroundStyle(Color.spotPurple)
                        .frame(width: 46, height: 46)
                        .background(Color.spotLavender, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(selectedVehicle.nickname).font(.headline)
                            if selectedVehicle.isCurrent {
                                Text("Today’s Vehicle")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.spotPurpleDark)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.spotLavender, in: Capsule())
                            }
                        }
                        Text(selectedVehicle.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.spotPurple)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(Color.spotPurple.opacity(0.18), lineWidth: 1)
                }
            } else if store.isLoading {
                ProgressView("Loading vehicles…")
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                Button("Add Vehicle", systemImage: "plus") { showingAddVehicle = true }
                    .buttonStyle(SpotSoonPrimaryButtonStyle())
            }

            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
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
