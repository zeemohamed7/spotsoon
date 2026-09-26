import SwiftUI

/// A deliberately compact, public-feed representation of a parking signal.
/// Private handover details and lifecycle controls belong in LiveHandoverView.
struct SignalRowView: View {
    let store: SignalStore
    let signal: ParkingSignal
    let now: Date
    let claim: () -> Void
    let resume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(signal.campus.title) — \(signal.zone)")
                        .font(.headline)
                        .foregroundStyle(Color.spotTextPrimary)
                    Text(leavingText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.spotAccent)
                }
                Spacer(minLength: 8)
                Text(signal.status.rawValue.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.spotAccentStrong)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.spotAccentSoft, in: Capsule())
            }

            Text(signal.userState(for: store.userID).message)
                .font(.subheadline)
                .foregroundStyle(Color.spotTextSecondary)

            switch signal.compactAction(for: store.userID) {
            case .claim:
                Button("Claim") { claim() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.spotAccent)
                    .disabled(store.isPerformingAction(on: signal.id))
            case .resumeHandover:
                Button("Resume Handover", systemImage: "arrow.up.forward.app.fill") {
                    resume()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.spotAccent)
            case .none:
                EmptyView()
            }

            if store.isPerformingAction(on: signal.id) {
                ProgressView("Updating…")
                    .font(.caption)
            }
            if let error = store.actionErrors[signal.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.spotError)
            }
        }
        .padding(14)
        .background(Color.spotSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.spotBorder, lineWidth: 1)
        }
    }

    private var leavingText: String {
        guard signal.leavingAt > now else { return "Leaving now" }
        let minutes = max(1, Int(ceil(signal.leavingAt.timeIntervalSince(now) / 60)))
        return "Leaving in \(minutes)m"
    }
}
