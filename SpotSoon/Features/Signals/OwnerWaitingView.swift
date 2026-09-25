import SwiftUI

struct OwnerWaitingView: View {
    let store: SignalStore
    let signal: ParkingSignal
    let vehicleStore: VehicleStore
    let locationStore: LocationStore
    @State private var confirmingCancellation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 28) {
                        Label("BROADCASTING LIVE", systemImage: "circle.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Color.green.opacity(0.08), in: Capsule())

                        radar(at: context.date)

                        VStack(spacing: 5) {
                            Text(countdown(at: context.date))
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.spotInk)
                            Text("Signal Active — Waiting for Driver")
                                .font(.headline)
                            Text("Waiting for claimant…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        details

                        Text("When claimed, you’ll receive matching vehicle details and a private visual token.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(Color.spotLavender.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))

                        if store.isPerformingAction(on: signal.id) {
                            ProgressView("Cancelling signal…")
                        }
                        if let error = store.actionErrors[signal.id] {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }

                        Button("Cancel Signal", role: .destructive) {
                            confirmingCancellation = true
                        }
                        .font(.headline)
                        .disabled(store.isPerformingAction(on: signal.id))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }
            }
        }
        .background(Color.spotLavender.opacity(0.28))
        .confirmationDialog(
            "Cancel this signal?",
            isPresented: $confirmingCancellation,
            titleVisibility: .visible
        ) {
            Button("Cancel Signal", role: .destructive) {
                Task { await store.perform(.cancel, on: signal) }
            }
            Button("Keep Signal", role: .cancel) {}
        } message: {
            Text("This removes the signal from the live campus map.")
        }
    }

    private var header: some View {
        HStack {
            SpotSoonLogo(compact: true)
            Spacer()
            Text("Active Coordination")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            NavigationLink {
                SettingsView(vehicleStore: vehicleStore, locationStore: locationStore)
            } label: {
                Image(systemName: "person.fill")
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.spotPurple, in: Circle())
            }
            .accessibilityLabel("Profile and settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.white)
    }

    private func radar(at date: Date) -> some View {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
        return ZStack {
            Circle()
                .stroke(Color.spotPurple.opacity(0.12 * (1 - phase)), lineWidth: 2)
                .frame(width: 220, height: 220)
                .scaleEffect(0.76 + phase * 0.3)
            Circle().stroke(Color.spotPurple.opacity(0.2), lineWidth: 2).frame(width: 168, height: 168)
            Circle().stroke(Color.spotPurple.opacity(0.28), lineWidth: 2).frame(width: 116, height: 116)
            Image(systemName: "car.fill")
                .font(.title)
                .foregroundStyle(Color.spotPurple)
                .frame(width: 70, height: 70)
                .background(.white, in: Circle())
                .shadow(color: Color.spotPurple.opacity(0.15), radius: 14)
        }
        .frame(height: 230)
    }

    private var details: some View {
        VStack(spacing: 17) {
            detailRow("Zone", "\(signal.campus.title) — \(signal.zone)")
            detailRow("Leaving", leavingText)
            if let hint = store.localBayHint(for: signal.id) {
                detailRow("Hint", hint)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var leavingText: String {
        let seconds = signal.leavingAt.timeIntervalSinceNow
        if seconds <= 30 { return "Now" }
        return "in ~\(max(1, Int(ceil(seconds / 60)))) min"
    }

    private func countdown(at date: Date) -> String {
        let seconds = max(0, Int(signal.expiresAt.timeIntervalSince(date)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
