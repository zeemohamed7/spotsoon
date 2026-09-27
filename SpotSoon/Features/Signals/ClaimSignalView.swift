import SwiftUI

struct ClaimSignalView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SignalStore
    let vehicleStore: VehicleStore
    let signal: ParkingSignal
    let onClaimed: () -> Void
    @State private var selectedVehicleID: UUID?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Capsule()
                        .fill(Color.spotTextMuted.opacity(0.28))
                        .frame(width: 44, height: 5)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("INCOMING ARRIVAL")
                                .font(.caption.bold())
                                .tracking(1)
                                .foregroundStyle(Color.spotAccent)
                            Text("Claim Spot")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.spotTextPrimary)
                        }
                        Spacer()
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .foregroundStyle(Color.spotTextSecondary)
                            .frame(width: 42, height: 42)
                            .background(Color.spotSurfaceElevated, in: Circle())
                    }

                    signalCard

                    VehiclePickerView(
                        title: "Vehicle you’re arriving in",
                        store: vehicleStore,
                        selectedVehicleID: $selectedVehicleID
                    )

                    Label(
                        "Your vehicle details are shared only with the departing driver during this active handover.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.spotTextSecondary)

                    if let error = store.actionErrors[signal.id] {
                        Text(error).font(.caption).foregroundStyle(Color.spotError)
                    }
                    if store.isPerformingAction(on: signal.id) {
                        ProgressView("Claiming signal…")
                            .frame(maxWidth: .infinity)
                    }

                    Button("Claim This Spot →") { validateAndConfirm() }
                        .buttonStyle(SpotSoonPrimaryButtonStyle())
                        .disabled(
                            selectedVehicleID == nil
                                || store.isPerformingAction(on: signal.id)
                        )

                    Text("The handover window remains active for five minutes after the departure time.")
                        .font(.caption)
                        .foregroundStyle(Color.spotTextSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .spotScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(store.isPerformingAction(on: signal.id))
            .alert("Claim this parking signal?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Claim This Spot") {
                    Task {
                        if await store.claim(signal, claimantVehicleID: selectedVehicleID) {
                            onClaimed()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Head to \(signal.campus.title), \(signal.zone), and use the private handover pass to identify each other.")
            }
        }
    }

    private var signalCard: some View {
        HStack(spacing: 12) {
            Text("P")
                .font(.headline.bold())
                .foregroundStyle(Color.spotAccent)
                .frame(width: 48, height: 48)
                .background(Color.spotAccentSoft, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) {
                Text("\(signal.campus.title) — \(signal.zone)")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(Color.spotSuccess).frame(width: 6, height: 6)
                    Text(leavingText).foregroundStyle(Color.spotSuccess)
                }
                .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.spotSurfaceElevated, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.spotBorder, lineWidth: 1)
        }
    }

    private var leavingText: String {
        let seconds = signal.leavingAt.timeIntervalSinceNow
        if seconds <= 30 { return "Leaving now" }
        return "Leaving in \(max(1, Int(ceil(seconds / 60))))m"
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
