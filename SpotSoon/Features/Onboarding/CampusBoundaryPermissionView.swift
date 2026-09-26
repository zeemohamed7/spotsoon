import SwiftUI

struct CampusBoundaryPermissionView: View {
    let isRequesting: Bool
    let backAction: () -> Void
    let enableAction: () -> Void
    let notNowAction: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: backAction)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.spotTextSecondary)
                Spacer()
                Text("SPOTSOON CAMPUS RADAR")
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundStyle(Color.spotAccent)
                Spacer()
                Color.clear.frame(width: 24, height: 24)
            }

            Spacer(minLength: 8)

            boundaryDiagram

            VStack(spacing: 10) {
                Text("Campus Boundary Verification")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.spotTextPrimary)
                Text("SpotSoon confirms that you are inside an approved student parking area before creating a signal.")
                    .font(.body)
                    .foregroundStyle(Color.spotTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                detail("Designated campus boundary", "Only verifies presence within an authorized perimeter.", "viewfinder")
                detail("Zero background tracking", "Location is requested only while you use the app.", "shield")
                detail("No exact bay pinpointing", "Your precise position is never shared in the signal feed.", "hand.raised")
            }

            Spacer()

            Button(action: enableAction) {
                if isRequesting {
                    ProgressView().tint(Color.spotAccentForeground)
                } else {
                    Label("Enable Campus Location", systemImage: "location.fill")
                }
            }
            .buttonStyle(SpotSoonPrimaryButtonStyle())
            .disabled(isRequesting)

            Button("Not Now", action: notNowAction)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.spotTextSecondary)
        }
        .padding(26)
        .spotScreenBackground()
    }

    private var boundaryDiagram: some View {
        ZStack {
            ForEach([170.0, 126.0, 82.0], id: \.self) { diameter in
                Circle()
                    .stroke(Color.spotAccent.opacity(0.22), lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
            }
            Image(systemName: "location.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.spotAccentForeground)
                .frame(width: 58, height: 58)
                .background(Color.spotAccent.gradient, in: Circle())
                .shadow(color: Color.spotAccent.opacity(0.25), radius: 18)
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Campus verification perimeter")
    }

    private func detail(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(Color.spotAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Color.spotTextSecondary)
            }
        }
    }
}
