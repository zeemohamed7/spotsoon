import SwiftUI

struct LiveHandoverContainer: View {
    let store: SignalStore
    let signal: ParkingSignal
    let close: (() -> Void)?
    let completed: (ParkingSignal) -> Void
    @State private var trackingStore: ApproachTrackingStore

    init(
        store: SignalStore,
        signal: ParkingSignal,
        repository: any ApproachTrackingRepository,
        locationProvider: any ApproachLocationProviding,
        close: (() -> Void)?,
        completed: @escaping (ParkingSignal) -> Void
    ) {
        self.store = store
        self.signal = signal
        self.close = close
        self.completed = completed
        _trackingStore = State(initialValue: ApproachTrackingStore(
            repository: repository,
            provider: locationProvider,
            signalID: signal.id,
            isClaimant: signal.claimedBy == store.userID
        ))
    }

    var body: some View {
        LiveHandoverView(
            store: store,
            signal: signal,
            trackingStore: trackingStore,
            close: close,
            completed: completed
        )
    }
}

struct LiveHandoverView: View {
    @Environment(\.scenePhase) private var scenePhase
    let store: SignalStore
    let signal: ParkingSignal
    let trackingStore: ApproachTrackingStore
    let close: (() -> Void)?
    let completed: (ParkingSignal) -> Void

    @State private var confirmation: ParkingSignal.LifecycleAction?
    @State private var passPresentation = HandoverPassPresentationState()

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

                    if [.claimed, .arrived].contains(signal.status) {
                        ApproachMapCard(store: trackingStore)
                    }

                    if let hint = details?.parkingHint {
                        parkingHintCard(hint)
                    }

                    if let counterpartVehicle {
                        vehicleCard(counterpartVehicle)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading private handover details…")
                                .font(.subheadline)
                                .foregroundStyle(Color.spotTextSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .handoverCard()
                    }

                    if let details, let pass = details.pass {
                        compactPass(pass)
                    }

                    actionArea

                    if store.isPerformingAction(on: signal.id) {
                        ProgressView("Updating handover…")
                            .frame(maxWidth: .infinity)
                    }

                    if let error = store.actionErrors[signal.id] {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.spotError)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.spotError.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                    }

                    Label(
                        "Visually verify only when safely stopped. Do not block traffic or confront another driver.",
                        systemImage: "shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.spotTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .background(Color.spotBackground.ignoresSafeArea())
        .task { await trackingStore.start() }
        .onDisappear { Task { await trackingStore.stop() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await trackingStore.stop() } }
            else { Task { await trackingStore.start() } }
        }
        .onChange(of: signal.status) { _, status in
            if ![.claimed, .arrived].contains(status) {
                Task { await trackingStore.stop() }
            }
        }
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
        .fullScreenCover(isPresented: Binding(
            get: { passPresentation.isPresented },
            set: { isPresented in
                if !isPresented { passPresentation.close() }
            }
        )) {
            if let details {
                HandoverPassView(
                    details: details,
                    vehicle: counterpartVehicle,
                    vehicleLabel: isOwner ? "VEHICLE ARRIVING" : "VEHICLE LEAVING",
                    instructions: isOwner
                        ? "Use this pass to visually match the arriving driver’s pass and vehicle."
                        : "Show this pass to the departing driver so they can visually match the colour, symbol, number, and vehicle.",
                    confirmationTitle: isOwner
                        ? "I See the Arriving Vehicle"
                        : "I See the Driver’s Vehicle"
                )
            }
        }
    }

    private var header: some View {
        HStack {
            SpotSoonLogo(compact: true)
            Spacer()
            Text("Live Handover")
                .font(.headline)
                .foregroundStyle(Color.spotTextPrimary)
            Circle()
                .fill(Color.spotSuccess)
                .frame(width: 8, height: 8)
            if let close {
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(Color.spotTextSecondary)
                    .frame(width: 40, height: 40)
                    .background(Color.spotSurfaceElevated, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.spotSurface)
    }

    private var statusHeading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(statusLabel)
                .font(.caption2.bold())
                .tracking(0.7)
                .foregroundStyle(Color.spotAccentStrong)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.spotAccentSoft, in: Capsule())

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.spotTextPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.spotTextSecondary)
        }
    }

    private var parkingAreaCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "parkingsign.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.spotAccent)
                .frame(width: 46, height: 46)
                .background(Color.spotAccentSoft, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("PARKING AREA")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.spotTextSecondary)
                Text(signal.zone)
                    .font(.headline)
                    .foregroundStyle(Color.spotTextPrimary)
                Text(signal.campus.title)
                    .font(.caption)
                    .foregroundStyle(Color.spotTextSecondary)
            }
            Spacer()
            Text(signal.status.rawValue.capitalized)
                .font(.caption2.bold())
                .foregroundStyle(Color.spotSuccess)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.spotSuccess.opacity(0.1), in: Capsule())
        }
        .padding(16)
        .handoverCard()
    }

    private func vehicleCard(_ vehicle: VehicleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isOwner ? "INCOMING VEHICLE" : "DEPARTING VEHICLE")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.spotTextSecondary)
                Spacer()
                Label("Private", systemImage: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.spotAccent)
            }

            Divider()

            HStack(spacing: 13) {
                Image(systemName: "car.side.fill")
                    .font(.title3)
                    .foregroundStyle(Color.spotAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.spotAccentSoft, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.description)
                        .font(.headline)
                        .foregroundStyle(Color.spotTextPrimary)
                    if let plate = vehicle.plateSuffix {
                        Text("Plate ending ••• \(plate)")
                            .font(.caption)
                            .foregroundStyle(Color.spotTextSecondary)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .handoverCard()
    }

    private func parkingHintCard(_ hint: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3)
                .foregroundStyle(Color.spotAccent)
                .frame(width: 42, height: 42)
                .background(Color.spotAccentSoft, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("PRIVATE PARKING HINT")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.spotTextSecondary)
                Text(hint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spotTextPrimary)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(Color.spotAccent)
        }
        .padding(16)
        .handoverCard()
    }

    private func compactPass(_ pass: HandoverDetails.Pass) -> some View {
        Button {
            passPresentation.show()
        } label: {
            compactPassContent(pass, prompt: "Show Handover Pass")
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full-screen windshield pass")
    }

    private func compactPassContent(_ pass: HandoverDetails.Pass, prompt: String) -> some View {
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
            Label(prompt, systemImage: "rectangle.portrait.and.arrow.forward")
                .font(.caption.weight(.semibold))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(passColor(pass.color).gradient, in: RoundedRectangle(cornerRadius: 17))
    }

    @ViewBuilder
    private var actionArea: some View {
        switch (signal.status, isOwner) {
        case (.claimed, true):
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
        .foregroundStyle(Color.spotTextSecondary)
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(Color.spotSurfaceElevated, in: RoundedRectangle(cornerRadius: 14))
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
        case (.claimed, true): "Someone is heading there"
        case (.claimed, false): "You’re heading there"
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
                    .foregroundStyle(Color.spotTextSecondary)
                    .frame(width: 42, height: 42)
                    .background(Color.spotSurfaceElevated, in: Circle())
            }
            .padding(18)

            Spacer()

            VStack(spacing: 22) {
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.spotAccentForeground)
                    .frame(width: 82, height: 82)
                    .background(Color.spotAccent.gradient, in: Circle())
                    .overlay { Circle().stroke(Color.spotAccent.opacity(0.2), lineWidth: 12) }
                    .shadow(color: Color.spotSuccess.opacity(0.22), radius: 24)

                VStack(spacing: 8) {
                    Text("Spot Secured!")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.spotTextPrimary)
                    Text("Handover completed successfully. Park safely and enjoy your day.")
                        .font(.body)
                        .foregroundStyle(Color.spotTextSecondary)
                        .multilineTextAlignment(.center)
                }

                Label("\(signal.zone) · \(signal.campus.title)", systemImage: "parkingsign.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spotTextPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.spotAccentSoft, in: Capsule())

                VStack(spacing: 6) {
                    Label("Handover complete", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(Color.spotSuccess)
                    Text("The signal has been removed from the active feed and its private handover details have been cleared.")
                        .font(.caption)
                        .foregroundStyle(Color.spotTextSecondary)
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
        .background(Color.spotBackground.ignoresSafeArea())
    }
}

private extension View {
    func handoverCard() -> some View {
        background(Color.spotSurface, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(Color.spotBorder, lineWidth: 1) }
    }
}
