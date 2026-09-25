import SwiftUI

struct LiveHandoverView: View {
    let store: SignalStore
    let signal: ParkingSignal
    let showPass: (HandoverDetails) -> Void
    let completed: (ParkingSignal) -> Void

    @State private var confirmation: ParkingSignal.LifecycleAction?

    private var isOwner: Bool { signal.createdBy == store.userID }
    private var details: HandoverDetails? { store.handover(for: signal) }
    private var counterpartVehicle: VehicleSnapshot? {
        details?.counterpartVehicle(for: signal, userID: store.userID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusHeading

                    parkingAreaCard

                    if let counterpartVehicle {
                        vehicleCard(counterpartVehicle)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading private handover details…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .handoverCard()
                    }

                    if let details, let pass = details.pass {
                        compactPass(pass, details: details)
                    }

                    actionArea

                    if store.isPerformingAction(on: signal.id) {
                        ProgressView("Updating handover…")
                            .frame(maxWidth: .infinity)
                    }

                    if let error = store.actionErrors[signal.id] {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                    }

                    Label(
                        "Visually verify only when safely stopped. Do not block traffic or confront another driver.",
                        systemImage: "shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .background(Color.spotLavender.opacity(0.28).ignoresSafeArea())
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation {
                Button(buttonTitle(for: confirmation), role: destructiveRole(for: confirmation)) {
                    perform(confirmation)
                }
                Button("Keep Handover", role: .cancel) { self.confirmation = nil }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var header: some View {
        HStack {
            SpotSoonLogo(compact: true)
            Spacer()
            Text("Live Handover")
                .font(.headline)
                .foregroundStyle(Color.spotInk)
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.white)
    }

    private var statusHeading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(statusLabel)
                .font(.caption2.bold())
                .tracking(0.7)
                .foregroundStyle(Color.spotPurpleDark)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.spotPurple.opacity(0.1), in: Capsule())

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.spotInk)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var parkingAreaCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "parkingsign.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.spotPurple)
                .frame(width: 46, height: 46)
                .background(Color.spotLavender, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("PARKING AREA")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(signal.zone)
                    .font(.headline)
                    .foregroundStyle(Color.spotInk)
                Text(signal.campus.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(signal.status.rawValue.capitalized)
                .font(.caption2.bold())
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.1), in: Capsule())
        }
        .padding(16)
        .handoverCard()
    }

    private func vehicleCard(_ vehicle: VehicleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isOwner ? "INCOMING VEHICLE" : "DEPARTING VEHICLE")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Private", systemImage: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.spotPurple)
            }

            Divider()

            HStack(spacing: 13) {
                Image(systemName: "car.side.fill")
                    .font(.title3)
                    .foregroundStyle(Color.spotPurple)
                    .frame(width: 44, height: 44)
                    .background(Color.spotLavender, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.description)
                        .font(.headline)
                        .foregroundStyle(Color.spotInk)
                    if let plate = vehicle.plateSuffix {
                        Text("Plate ending ••• \(plate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .handoverCard()
    }

    private func compactPass(_ pass: HandoverDetails.Pass, details: HandoverDetails) -> some View {
        Button {
            showPass(details)
        } label: {
            VStack(spacing: 12) {
                HStack {
                    Label("MUTUAL HANDOVER PASS", systemImage: "checkmark.shield.fill")
                        .font(.caption2.bold())
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                Text(pass.title.uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .tracking(1)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("Tap to show the full windshield pass")
                    .font(.caption)
                    .opacity(0.82)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(passColor(pass.color).gradient, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch (signal.status, isOwner) {
        case (.claimed, true):
            if let details {
                Button {
                    showPass(details)
                } label: {
                    Label("I See the Incoming Vehicle", systemImage: "eye.fill")
                }
                .buttonStyle(SpotSoonPrimaryButtonStyle())
            }
            waitingMessage("Waiting for the claimant to arrive")
            secondaryAction("Cancel Signal", role: .destructive, action: .cancel)

        case (.claimed, false):
            primaryAction("I’m Here — Waiting at the Parking Area", icon: "figure.wave", action: .arrive)
            secondaryAction("Release Claim", role: .destructive, action: .release)

        case (.arrived, true):
            primaryAction("I’ve Left — Space Is Vacant", icon: "checkmark", action: .vacate)
            secondaryAction("Cancel Signal", role: .destructive, action: .cancel)

        case (.arrived, false):
            waitingMessage("The departing driver knows you have arrived")
            secondaryAction("Release Claim", role: .destructive, action: .release)

        case (.vacated, true):
            waitingMessage("The claimant is confirming the result")

        case (.vacated, false):
            primaryAction("I Got the Spot", icon: "checkmark.circle.fill", action: .complete)
            secondaryAction("Spot Wasn’t Available", role: .destructive, action: .unavailable)

        default:
            EmptyView()
        }
    }

    private func primaryAction(_ title: String, icon: String, action: ParkingSignal.LifecycleAction) -> some View {
        Button {
            if action == .complete { perform(action) }
            else { confirmation = action }
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(SpotSoonPrimaryButtonStyle())
        .disabled(store.isPerformingAction(on: signal.id))
    }

    private func secondaryAction(
        _ title: String,
        role: ButtonRole? = nil,
        action: ParkingSignal.LifecycleAction
    ) -> some View {
        Button(title, role: role) { confirmation = action }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .disabled(store.isPerformingAction(on: signal.id))
    }

    private func waitingMessage(_ text: String) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text(text).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(Color.spotLavender.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusLabel: String {
        switch (signal.status, isOwner) {
        case (.claimed, true): "DRIVER APPROACHING"
        case (.claimed, false): "HEAD TO THE PARKING AREA"
        case (.arrived, true): "CLAIMANT HAS ARRIVED"
        case (.arrived, false): "ARRIVED AT PARKING AREA"
        case (.vacated, true): "SPACE VACATED"
        case (.vacated, false): "DRIVER HAS LEFT"
        default: "LIVE HANDOVER"
        }
    }

    private var title: String {
        switch (signal.status, isOwner) {
        case (.claimed, true): "Driver is on the way"
        case (.claimed, false): "Find the departing driver"
        case (.arrived, true): "Handing over the space"
        case (.arrived, false): "You’re at the parking area"
        case (.vacated, true): "You’ve left the space"
        case (.vacated, false): "The driver has left"
        default: "Live handover"
        }
    }

    private var subtitle: String {
        switch (signal.status, isOwner) {
        case (.claimed, true): "Look for the arriving vehicle and confirm the matching private pass."
        case (.claimed, false): "Locate the departing vehicle and verify the matching private pass."
        case (.arrived, true): "Visually verify the arriving vehicle, then confirm after you have safely pulled out."
        case (.arrived, false): "Wait safely and give the departing driver room to leave."
        case (.vacated, true): "The claimant is checking whether the parking space is available."
        case (.vacated, false): "Confirm whether you received the parking space."
        default: "Coordinate the handover safely."
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .arrive: "Tell the driver you’re here?"
        case .vacate: "Confirm that you’ve left?"
        case .release: "Release your claim?"
        case .cancel: "Cancel this signal?"
        case .unavailable: "Was the spot unavailable?"
        default: "Confirm action"
        }
    }

    private var confirmationMessage: String {
        switch confirmation {
        case .arrive: "The departing driver will see that you have arrived at the parking area."
        case .vacate: "The claimant will be asked to confirm whether they received the space."
        case .release: "The signal will become available again and the current handover pass will be invalidated."
        case .cancel: "This ends the handover and removes the signal from the active feed."
        case .unavailable: "This ends the handover and records that the space was unavailable."
        default: ""
        }
    }

    private func buttonTitle(for action: ParkingSignal.LifecycleAction) -> String {
        switch action {
        case .arrive: "I’m Here"
        case .vacate: "I’ve Left"
        case .release: "Release Claim"
        case .cancel: "Cancel Signal"
        case .unavailable: "Spot Wasn’t Available"
        case .complete: "I Got the Spot"
        case .claim: "Claim"
        case .showPass: "Show Pass"
        }
    }

    private func destructiveRole(for action: ParkingSignal.LifecycleAction) -> ButtonRole? {
        [.release, .cancel, .unavailable].contains(action) ? .destructive : nil
    }

    private func perform(_ action: ParkingSignal.LifecycleAction) {
        confirmation = nil
        Task {
            if await store.perform(action, on: signal), action == .complete {
                completed(signal)
            }
        }
    }

    private func passColor(_ color: HandoverDetails.PassColor) -> Color {
        switch color {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow.mix(with: .orange, by: 0.25)
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}

struct HandoverCompleteView: View {
    let signal: ParkingSignal
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close", systemImage: "xmark", action: done)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .background(Color.spotLavender, in: Circle())
            }
            .padding(18)

            Spacer()

            VStack(spacing: 22) {
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 82, height: 82)
                    .background(Color.spotPurple.gradient, in: Circle())
                    .overlay { Circle().stroke(Color.spotPurple.opacity(0.2), lineWidth: 12) }
                    .shadow(color: Color.green.opacity(0.22), radius: 24)

                VStack(spacing: 8) {
                    Text("Spot Secured!")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.spotInk)
                    Text("Handover completed successfully. Park safely and enjoy your day.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Label("\(signal.zone) · \(signal.campus.title)", systemImage: "parkingsign.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spotInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.spotLavender, in: Capsule())

                VStack(spacing: 6) {
                    Label("Handover complete", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("The signal has been removed from the active feed and its private handover details have been cleared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .handoverCard()
            }
            .padding(24)

            Spacer()

            Button("Done & Back to Map", action: done)
                .buttonStyle(SpotSoonPrimaryButtonStyle())
                .padding(24)
        }
        .background(Color.spotLavender.opacity(0.22).ignoresSafeArea())
    }
}

private extension View {
    func handoverCard() -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(Color.black.opacity(0.06), lineWidth: 1) }
    }
}
