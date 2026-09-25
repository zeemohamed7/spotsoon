#if DEBUG
import SwiftUI

@MainActor
private final class PreviewParkingSignalRepository: ParkingSignalRepository {
    var feed: SignalFeed

    init(feed: SignalFeed) { self.feed = feed }

    func fetchFeed(now: Date) async throws -> SignalFeed { feed }
    func publish(_ request: PublishParkingSignalRequest) async throws -> ParkingSignal { request.signal }
    func claim(signalID: UUID, claimantVehicleID: UUID) async throws -> ParkingSignal { try signal(id: signalID) }
    func markArrived(signalID: UUID) async throws -> ParkingSignal { try signal(id: signalID) }
    func releaseClaim(signalID: UUID) async throws -> ParkingSignal { try signal(id: signalID) }
    func cancel(signalID: UUID) async throws -> ParkingSignal { try signal(id: signalID) }
    func markVacated(signalID: UUID) async throws -> ParkingSignal { try signal(id: signalID) }
    func complete(signalID: UUID) async throws -> ParkingSignal { try signal(id: signalID) }
    func markUnavailable(signalID: UUID) async throws -> ParkingSignal { try signal(id: signalID) }
    func observe(_ receive: @escaping @MainActor (SignalEvent) async -> Void) async throws {}

    private func signal(id: UUID) throws -> ParkingSignal {
        guard let signal = feed.signals.first(where: { $0.id == id }) else {
            throw ParkingSignalRepositoryError.transitionUnavailable
        }
        return signal
    }
}

@MainActor
private final class PreviewZoneRepository: ParkingZoneRepository {
    func fetchActiveZones() async throws -> [ParkingZone] { [.campusAStudent] }
}

@MainActor
private final class PreviewLocationProvider: LocationProviding {
    var authorizationStatus: LocationAuthorizationState { .authorized }
    func requestWhenInUseAuthorization() async -> LocationAuthorizationState { .authorized }
    func requestLocation() async throws -> LocationReading {
        LocationReading(
            latitude: ParkingZone.campusAStudent.latitude,
            longitude: ParkingZone.campusAStudent.longitude,
            horizontalAccuracy: 8,
            timestamp: .now
        )
    }
}

@MainActor
private final class PreviewVehicleRepository: VehicleRepository {
    let vehicle: Vehicle
    init(vehicle: Vehicle) { self.vehicle = vehicle }
    func fetchVehicles() async throws -> [Vehicle] { [vehicle] }
    func create(_ vehicle: ValidatedVehicle, userID: UUID) async throws -> Vehicle { self.vehicle }
    func update(id: UUID, vehicle: ValidatedVehicle) async throws -> Vehicle { self.vehicle }
    func delete(id: UUID) async throws {}
    func setCurrent(id: UUID) async throws -> Vehicle { vehicle }
}

@MainActor
private struct SignalLifecyclePreview: View {
    private let store: SignalStore
    private let vehicleStore: VehicleStore
    private let zoneStore: ParkingZoneStore
    private let locationStore: LocationStore

    init() {
        let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let claimant = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let signalID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let now = Date.now
        let signal = ParkingSignal(
            id: signalID,
            createdBy: owner,
            campus: .campusA,
            zone: "A2",
            leavingAt: now.addingTimeInterval(300),
            expiresAt: now.addingTimeInterval(600),
            status: .arrived,
            createdAt: now,
            claimedBy: claimant,
            claimedAt: now
        )
        let details = HandoverDetails(
            signalID: signalID,
            passColor: .purple,
            symbolName: "hare.fill",
            confirmationNumber: "42",
            ownerVehicle: Self.kiaSnapshot,
            claimantVehicle: VehicleSnapshot(
                nickname: "Campus run",
                color: "Blue",
                vehicleType: .suv,
                make: "Nissan",
                model: "X-Trail",
                plateSuffix: "127"
            ),
            createdAt: now
        )
        let vehicle = Vehicle(
            id: UUID(), userID: owner, nickname: "My K5", color: "Midnight grey",
            vehicleType: .sedan, make: "Kia", model: "K5", plateSuffix: "404",
            isCurrent: true, createdAt: now, updatedAt: now
        )
        store = SignalStore(
            repository: PreviewParkingSignalRepository(
                feed: SignalFeed(signals: [signal], handoverDetails: [signalID: details])
            ),
            userID: owner
        )
        vehicleStore = VehicleStore(repository: PreviewVehicleRepository(vehicle: vehicle), userID: owner)
        zoneStore = ParkingZoneStore(repository: PreviewZoneRepository())
        locationStore = LocationStore(provider: PreviewLocationProvider())
    }

    var body: some View {
        SignalListView(
            store: store,
            vehicleStore: vehicleStore,
            zoneStore: zoneStore,
            locationStore: locationStore
        )
    }

    private static let kiaSnapshot = VehicleSnapshot(
        nickname: "My K5", color: "Midnight grey", vehicleType: .sedan,
        make: "Kia", model: "K5", plateSuffix: "404"
    )
}

#Preview("Creator handover") {
    SignalLifecyclePreview()
}

#Preview("Full handover pass") {
    HandoverPassView(details: HandoverDetails(
        signalID: UUID(),
        passColor: .blue,
        symbolName: "bird.fill",
        confirmationNumber: "08",
        ownerVehicle: VehicleSnapshot(
            nickname: "My K5", color: "Midnight grey", vehicleType: .sedan,
            make: "Kia", model: "K5", plateSuffix: "404"
        ),
        claimantVehicle: nil,
        createdAt: .now
    ))
}
#endif
