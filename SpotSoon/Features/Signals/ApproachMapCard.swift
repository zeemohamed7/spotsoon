import MapKit
import SwiftUI

struct ApproachMapCard: View {
    let store: ApproachTrackingStore

    private var region: MKCoordinateRegion? {
        guard let location = store.location else { return nil }
        let points = [location.owner, location.claimant].compactMap { $0 }
        let latitudes = points.map(\.latitude), longitudes = points.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLng = longitudes.min(), let maxLng = longitudes.max() else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.0015, (maxLat - minLat) * 1.8),
                longitudeDelta: max(0.0015, (maxLng - minLng) * 1.8)
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TEMPORARY LIVE APPROACH")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.spotTextSecondary)
                    Text(store.approachBand?.rawValue ?? "Approach location")
                        .font(.headline)
                        .foregroundStyle(Color.spotTextPrimary)
                }
                Spacer()
                Label(store.freshness.label, systemImage: freshnessIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(freshnessColor)
            }

            if let location = store.location, let region {
                Map(position: .constant(.region(region)), interactionModes: []) {
                    Annotation("Parked vehicle", coordinate: location.owner.coordinate) {
                        marker(icon: "parkingsign", color: .spotAccent)
                    }
                    if let claimant = location.claimant {
                        Annotation("Approaching vehicle", coordinate: claimant.coordinate) {
                            marker(icon: "car.fill", color: .spotSuccess)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .accessibilityLabel("Approach map showing the parked vehicle and authorized approaching vehicle location")

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let distance = store.formattedDistance() {
                            Text(distance).font(.subheadline.bold())
                        } else {
                            Text("Other participant is not currently sharing")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Approximate GPS position · parked accuracy ±\(Int(location.owner.horizontalAccuracy.rounded())) m")
                            .font(.caption2)
                            .foregroundStyle(Color.spotTextSecondary)
                    }
                    Spacer()
                    if let accuracy = location.claimant?.horizontalAccuracy {
                        Text("±\(Int(accuracy.rounded())) m")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.spotTextSecondary)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading authorized parked position…")
                        .font(.subheadline)
                        .foregroundStyle(Color.spotTextSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }

            if store.isClaimant { claimantControls }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(Color.spotError)
            }
        }
        .padding(16)
        .background(Color.spotSurface, in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).stroke(Color.spotBorder, lineWidth: 1) }
    }

    @ViewBuilder
    private var claimantControls: some View {
        Text("Your approximate location is shared only with the departing driver while this screen is open. You can pause at any time. GPS does not identify an exact bay, so use the private hint, vehicles, and matching pass.")
            .font(.caption)
            .foregroundStyle(Color.spotTextSecondary)

        switch store.authorizationState {
        case .denied, .restricted:
            Button("Open Location Settings", systemImage: "gear") { store.openSettings() }
                .buttonStyle(.bordered)
        case .notRequested, .authorized:
            if store.isSharing {
                Button("Pause Live Approach", systemImage: "pause.circle.fill") {
                    Task { await store.pauseSharing() }
                }
                .buttonStyle(.bordered)
                .tint(Color.spotAccent)
                .disabled(store.isWorking)
                .accessibilityLabel("Pause live approach location sharing")
            } else {
                Button("Share Live Approach", systemImage: "location.fill") {
                    Task { await store.enableSharing() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.spotAccent)
                .disabled(store.isWorking)
                .accessibilityLabel("Share live approach location")
            }
        }

        if store.isWaitingForReading {
            ProgressView("Waiting for a fresh, accurate reading…")
                .font(.caption)
        }
    }

    private func marker(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(color, in: Circle())
            .overlay { Circle().stroke(.white, lineWidth: 2) }
            .shadow(radius: 4)
    }

    private var freshnessIcon: String {
        switch store.freshness {
        case .active: "location.fill"
        case .waiting: "location.magnifyingglass"
        case .paused: "pause.circle.fill"
        case .stale: "exclamationmark.circle.fill"
        }
    }

    private var freshnessColor: Color {
        switch store.freshness {
        case .active: .spotSuccess
        case .waiting, .paused: .spotTextSecondary
        case .stale: .spotWarning
        }
    }
}
