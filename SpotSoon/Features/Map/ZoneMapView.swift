import MapKit
import SwiftUI

struct ZoneMapView: View {
    let zoneStore: ParkingZoneStore
    let locationStore: LocationStore
    @State private var camera: MapCameraPosition

    init(zoneStore: ParkingZoneStore, locationStore: LocationStore) {
        self.zoneStore = zoneStore
        self.locationStore = locationStore
        _camera = State(initialValue: .region(Self.region(for: .campusAStudent)))
    }

    var body: some View {
        Map(position: $camera, selection: Binding(
            get: { zoneStore.selectedZoneID },
            set: { zoneStore.selectedZoneID = $0 }
        )) {
            ForEach(zoneStore.zones) { zone in
                MapCircle(center: zone.coordinate, radius: zone.verificationRadiusMeters)
                    .foregroundStyle(.blue.opacity(0.14))
                    .stroke(.blue, lineWidth: 2)
                Marker(zone.name, systemImage: "parkingsign.circle.fill", coordinate: zone.coordinate)
                    .tag(zone.id)
            }
            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .overlay(alignment: .bottomTrailing) {
            if let zone = zoneStore.selectedZone {
                Button("Recenter parking area", systemImage: "scope") {
                    withAnimation { camera = .region(Self.region(for: zone)) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .padding(12)
            }
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
        .accessibilityLabel("Campus parking map")
    }

    private static func region(for zone: ParkingZone) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: zone.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0045, longitudeDelta: 0.0045)
        )
    }
}
