import SwiftUI

struct LocationPermissionExplanationView: View {
    let allow: () -> Void
    let notNow: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.spotAccent)
                Text("Verify the parking area")
                    .font(.title2.bold())
                Text("SpotSoon uses your location to confirm that you are near the selected student car park before sharing a spot.")
                    .multilineTextAlignment(.center)
                Text("SpotSoon requests a fresh reading only when you publish. It does not continuously track you or store location history.")
                    .font(.subheadline)
                    .foregroundStyle(Color.spotTextSecondary)
                    .multilineTextAlignment(.center)
                Button("Allow Location", action: allow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Not Now", role: .cancel, action: notNow)
            }
            .padding(28)
            .spotScreenBackground()
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
