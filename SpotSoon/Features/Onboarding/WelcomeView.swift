import SwiftUI

struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label("SpotSoon Campus", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.spotAccent)
                    .labelStyle(.titleAndIcon)

                SpotSoonLogo()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Spend less time\nsearching.")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.spotTextPrimary)
                    Text("Coordinate live parking handovers with other students across campus.")
                        .font(.body)
                        .foregroundStyle(Color.spotTextSecondary)
                }

                VStack(spacing: 22) {
                    benefit(
                        "Real-time spot swap",
                        detail: "See departures and connect to a parking handover as it happens."
                    )
                    benefit(
                        "Campus verified",
                        detail: "Publishing is limited to approved student parking areas."
                    )
                    benefit(
                        "Location on your terms",
                        detail: "Verify a campus zone, then optionally share an approximate approach during an active handover."
                    )
                }

                VStack(spacing: 12) {
                    Button(action: continueAction) {
                        Label("Get Started", systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(SpotSoonPrimaryButtonStyle())

                    Text("Continue with a private anonymous account. Polytechnic SSO may be added in a later phase.")
                        .font(.caption)
                        .foregroundStyle(Color.spotTextSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 28)
        }
        .spotScreenBackground()
    }

    private func benefit(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.spotAccent)
                .frame(width: 28, height: 28)
                .background(Color.spotAccentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Color.spotTextSecondary)
            }
        }
    }
}
