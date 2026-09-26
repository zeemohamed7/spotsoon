import MapKit
import SwiftUI

struct ZoneMapView: View {
    let zoneStore: ParkingZoneStore
    let locationStore: LocationStore
    let signalCounts: [String: Int]
    @State private var camera: MapCameraPosition
    @State private var didApplyInitialFocus = false

    init(
        zoneStore: ParkingZoneStore,
        locationStore: LocationStore,
        signalCounts: [String: Int] = [:]
    ) {
        self.zoneStore = zoneStore
        self.locationStore = locationStore
        self.signalCounts = signalCounts
        _camera = State(initialValue: .region(Self.overviewRegion(for: ParkingZone.supportedDefaults)))
    }

    var body: some View {
        Map(position: $camera, selection: Binding(
            get: { zoneStore.selectedZoneID },
            set: { id in
                guard let id, zoneStore.selectZone(id: id) else { return }
                locationStore.invalidateVerification()
            }
        )) {
            ForEach(zoneStore.zones) { zone in
                MapCircle(center: zone.coordinate, radius: zone.verificationRadiusMeters)
                    .foregroundStyle(circleColor(for: zone).opacity(zone.id == zoneStore.selectedZoneID ? 0.2 : 0.07))
                    .stroke(circleColor(for: zone), lineWidth: zone.id == zoneStore.selectedZoneID ? 3 : 1)
                    .mapOverlayLevel(level: .aboveLabels)
                Marker(
                    "\(zone.name) · \(signalCounts[zone.id, default: 0]) active",
                    systemImage: zone.id == zoneStore.selectedZoneID
                        ? "parkingsign.circle.fill" : "parkingsign.circle",
                    coordinate: zone.coordinate
                )
                    .tint(zone.id == zoneStore.selectedZoneID ? Color.spotAccent : Color.spotTextMuted)
                    .tag(zone.id)
            }
            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        // MapKit follows the system appearance and supplies its native dark map.
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .overlay(alignment: .bottomTrailing) {
            HStack {
                Button("Show both campuses", systemImage: "map") {
                    withAnimation { camera = .region(Self.overviewRegion(for: zoneStore.zones)) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .clipShape(Circle())
                if let zone = zoneStore.selectedZone {
                    Button("Recenter selected parking area", systemImage: "scope") {
                        withAnimation { camera = .region(Self.region(for: zone)) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                }
            }
            .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            if let zone = zoneStore.selectedZone {
                Text("\(Int(zone.verificationRadiusMeters)) m permitted parking area")
                    .font(.caption.weight(.medium))
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .onChange(of: zoneStore.selectedZoneID) { _, _ in
            if let zone = zoneStore.selectedZone {
                withAnimation { camera = .region(Self.region(for: zone)) }
            }
        }
        .onChange(of: zoneStore.zones.map(\.id)) { _, _ in
            guard !didApplyInitialFocus else { return }
            didApplyInitialFocus = true
            if let zone = zoneStore.selectedZone {
                camera = .region(Self.region(for: zone))
            } else {
                camera = .region(Self.overviewRegion(for: zoneStore.zones))
            }
        }
        .accessibilityLabel("Campus parking map")
    }

    private func circleColor(for zone: ParkingZone) -> Color {
        zone.id == zoneStore.selectedZoneID ? .spotAccent : .spotTextMuted
    }

    private static func region(for zone: ParkingZone) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: zone.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0045, longitudeDelta: 0.0045)
        )
    }

    private static func overviewRegion(for zones: [ParkingZone]) -> MKCoordinateRegion {
        guard let first = zones.first else { return region(for: .campusAStudent) }
        let latitudes = zones.map(\.latitude)
        let longitudes = zones.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? first.latitude
        let maximumLatitude = latitudes.max() ?? first.latitude
        let minimumLongitude = longitudes.min() ?? first.longitude
        let maximumLongitude = longitudes.max() ?? first.longitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.7, 0.0045),
                longitudeDelta: max((maximumLongitude - minimumLongitude) * 2.2, 0.0045)
            )
        )
    }
}
