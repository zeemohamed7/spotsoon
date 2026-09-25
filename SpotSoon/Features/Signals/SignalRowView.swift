import SwiftUI

struct SignalRowView: View {
    let store: SignalStore
    let signal: ParkingSignal
    let now: Date
    let claim: () -> Void
    let showPass: (HandoverDetails) -> Void
    @State private var confirmation: ParkingSignal.LifecycleAction?

    private var actions: Set<ParkingSignal.LifecycleAction> {
        signal.allowedActions(for: store.userID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(signal.campus.title) · \(signal.zone)").font(.headline)
            if signal.leavingAt > now {
                Text("Leaving in \(Int(ceil(signal.leavingAt.timeIntervalSince(now) / 60))) min")
            } else {
                Text("Leaving time reached")
            }
            Text("Status: \(signal.status.rawValue)")
                .font(.caption).foregroundStyle(.secondary)
            Text(signal.userState(for: store.userID).message)
                .font(.subheadline.weight(.medium))

            if let details = store.handover(for: signal) {
                if let pass = details.pass { HandoverPassCard(pass: pass) }
                if let vehicle = details.counterpartVehicle(for: signal, userID: store.userID) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signal.createdBy == store.userID ? "Vehicle arriving" : "Vehicle leaving")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(vehicle.description).font(.subheadline.weight(.medium))
                    }
                }
                if actions.contains(.showPass), details.pass != nil {
                    Button("Show Handover Pass", systemImage: "rectangle.portrait.and.arrow.forward") {
                        showPass(details)
                    }
                }
            }

            actionButtons

            if store.isPerformingAction(on: signal.id) {
                ProgressView("Updating handover…")
            }
            if let error = store.actionErrors[signal.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .disabled(store.isPerformingAction(on: signal.id))
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
                    let selected = confirmation
                    self.confirmation = nil
                    Task { await store.perform(selected, on: signal) }
                }
                Button("Cancel", role: .cancel) { self.confirmation = nil }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    @ViewBuilder private var actionButtons: some View {
        if actions.contains(.claim) {
            Button("Claim") { claim() }
        }
        if actions.contains(.arrive) {
            Button("I’m Here") { confirmation = .arrive }
        }
        if actions.contains(.vacate) {
            Button("I’ve Left") { confirmation = .vacate }
        }
        if actions.contains(.complete) {
            Button("I Got the Spot") {
                Task { await store.perform(.complete, on: signal) }
            }
        }
        if actions.contains(.unavailable) {
            Button("Spot Wasn’t Available", role: .destructive) { confirmation = .unavailable }
        }
        if actions.contains(.release) {
            Button("Release Claim", role: .destructive) { confirmation = .release }
        }
        if actions.contains(.cancel) {
            Button("Cancel Signal", role: .destructive) { confirmation = .cancel }
        }
    }

    private var confirmationTitle: String {
        guard let confirmation else { return "Confirm action" }
        return switch confirmation {
        case .release: "Release your claim?"
        case .cancel: "Cancel this signal?"
        case .arrive: "Tell the driver you’re here?"
        case .vacate: "Confirm that you’ve left?"
        case .unavailable: "Was the spot unavailable?"
        case .claim, .complete, .showPass: "Confirm action"
        }
    }

    private var confirmationMessage: String {
        switch confirmation {
        case .release: "The signal will become available again and this handover pass will be invalidated."
        case .cancel: "This ends the handover and removes it from everyone’s active feed."
        case .arrive: "The departing driver will be told that you have arrived."
        case .vacate: "The claimant will be asked whether they received the spot."
        case .unavailable: "This ends the handover and reports that the spot was not available."
        case .claim, .complete, .showPass, nil: ""
        }
    }

    private func buttonTitle(for action: ParkingSignal.LifecycleAction) -> String {
        switch action {
        case .release: "Release Claim"
        case .cancel: "Cancel Signal"
        case .arrive: "I’m Here"
        case .vacate: "I’ve Left"
        case .unavailable: "Spot Wasn’t Available"
        case .complete: "I Got the Spot"
        case .claim: "Claim"
        case .showPass: "Show Handover Pass"
        }
    }

    private func destructiveRole(for action: ParkingSignal.LifecycleAction) -> ButtonRole? {
        [.release, .cancel, .unavailable].contains(action) ? .destructive : nil
    }
}
