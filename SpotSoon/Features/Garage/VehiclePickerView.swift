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
                    .foregroundStyle(Color.spotTextSecondary)
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
                    .foregroundStyle(Color.spotAccent)
                }
            }

            if let selectedVehicle {
                HStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .foregroundStyle(Color.spotAccent)
                        .frame(width: 46, height: 46)
                        .background(Color.spotAccentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(selectedVehicle.nickname).font(.headline)
                            if selectedVehicle.isCurrent {
                                Text("Today’s Vehicle")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.spotAccentStrong)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.spotAccentSoft, in: Capsule())
                            }
                        }
                        Text(selectedVehicle.summary)
                            .font(.subheadline)
                            .foregroundStyle(Color.spotTextSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.spotAccent)
                }
                .padding(14)
                .background(Color.spotSurfaceElevated, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(Color.spotAccent.opacity(0.28), lineWidth: 1)
                }
            } else if store.isLoading {
                ProgressView("Loading vehicles…")
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                Button("Add Vehicle", systemImage: "plus") { showingAddVehicle = true }
                    .buttonStyle(SpotSoonPrimaryButtonStyle())
            }

            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(Color.spotError)
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
