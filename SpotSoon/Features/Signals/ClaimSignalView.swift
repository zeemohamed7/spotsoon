import SwiftUI

struct ClaimSignalView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SignalStore
    let vehicleStore: VehicleStore
    let signal: ParkingSignal
    @State private var selectedVehicleID: UUID?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                VehiclePickerView(
                    title: "Vehicle you’re arriving in",
                    store: vehicleStore,
                    selectedVehicleID: $selectedVehicleID
                )

                Section {
                    Text("Visually verify only when safely stopped. Do not block traffic or confront another driver.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Review Claim") { validateAndConfirm() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                }

                if let error = store.actionErrors[signal.id] {
                    Text(error).foregroundStyle(.red)
                }
                if store.isPerformingAction(on: signal.id) {
                    ProgressView("Claiming signal…")
                }
            }
            .disabled(store.isPerformingAction(on: signal.id))
            .navigationTitle("Claim signal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review Claim") { validateAndConfirm() }
                }
            }
            .interactiveDismissDisabled(store.isPerformingAction(on: signal.id))
            .alert("Claim this parking signal?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Claim") {
                    Task {
                        if await store.claim(signal, claimantVehicleID: selectedVehicleID) { dismiss() }
                    }
                }
            } message: {
                Text("Head to \(signal.campus.title), zone \(signal.zone), and use the private handover pass to identify each other.")
            }
        }
    }

    private func validateAndConfirm() {
        guard selectedVehicleID != nil else {
            store.setActionError("Select the vehicle you’re arriving in.", for: signal.id)
            return
        }
        store.clearActionError(for: signal.id)
        confirming = true
    }
}
