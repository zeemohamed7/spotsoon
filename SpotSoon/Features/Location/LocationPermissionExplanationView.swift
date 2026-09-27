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
                Text("SpotSoon uses a fresh approximate location to verify that a departing driver is inside the selected campus parking zone before publishing.")
                    .multilineTextAlignment(.center)
                Text("After a claim, the incoming driver may choose to share an approximate live approach with the departing owner. Sharing works only in the foreground while Live Handover is open, can be paused, and never uses Always Location.")
                    .font(.subheadline)
                    .foregroundStyle(Color.spotTextSecondary)
                    .multilineTextAlignment(.center)
                Text("Temporary coordinates are participant-protected. Claimant coordinates are cleared on release, and all coordinates are deleted when the handover ends. The private hint, vehicles, partial plate suffix, and matching pass remain the final identification method.")
                    .font(.caption)
                    .foregroundStyle(Color.spotTextMuted)
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
