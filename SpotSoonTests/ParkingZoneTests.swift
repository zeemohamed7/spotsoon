import CoreLocation
import XCTest
@testable import SpotSoon

final class ParkingZoneTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testParkingZoneDecodesDatabaseColumns() throws {
        let data = """
        {
          "id":"campus_a_student",
          "name":"Campus A Student Car Park",
          "campus":"campus_a",
          "landmark":"West of the stadium",
          "latitude":26.164736,
          "longitude":50.543676,
          "verification_radius_meters":140,
          "is_active":true,
          "created_at":"2026-09-25T12:00:00Z",
          "updated_at":"2026-09-25T12:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let zone = try decoder.decode(ParkingZone.self, from: data)

        XCTAssertEqual(zone.id, "campus_a_student")
        XCTAssertEqual(zone.name, "Campus A Student Car Park")
        XCTAssertEqual(zone.campus, .campusA)
        XCTAssertEqual(zone.landmark, "West of the stadium")
        XCTAssertEqual(zone.verificationRadiusMeters, 140)
        XCTAssertTrue(zone.isActive)
        XCTAssertTrue(zone.isSupported)
    }

    func testExactCentreAndClearlyInsideAreAccepted() {
        let verifier = ZoneVerifier()
        let centre = verifier.verify(
            zone: .campusAStudent,
            reading: reading(latitude: 26.164736, longitude: 50.543676, accuracy: 8),
            now: now
        )
        let inside = verifier.verify(
            zone: .campusAStudent,
            reading: reading(latitude: 26.165000, longitude: 50.543676, accuracy: 8),
            now: now
        )

        XCTAssertTrue(centre.accepted)
        XCTAssertEqual(centre.distanceMeters ?? -1, 0, accuracy: 0.01)
        XCTAssertTrue(inside.accepted)
        XCTAssertLessThan(inside.distanceMeters ?? .infinity, 140)
    }

    func testExactBoundaryIsAccepted() {
        let target = CLLocation(latitude: 26.166000, longitude: 50.543676)
        let centre = CLLocation(latitude: 26.164736, longitude: 50.543676)
        let measuredDistance = target.distance(from: centre)
        let zone = ParkingZone.testZone(radius: measuredDistance)

        let result = ZoneVerifier().verify(
            zone: zone,
            reading: reading(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude, accuracy: 0),
            now: now
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.distanceMeters ?? -1, measuredDistance, accuracy: 0.01)
    }

    func testAccuracyToleranceIsCappedAtTwentyFiveMetres() {
        let target = CLLocation(latitude: 26.166220, longitude: 50.543676)
        let centre = CLLocation(latitude: 26.164736, longitude: 50.543676)
        let distance = target.distance(from: centre)
        XCTAssertGreaterThan(distance, 140)
        XCTAssertLessThan(distance, 165)

        let accepted = ZoneVerifier().verify(
            zone: .campusAStudent,
            reading: reading(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude, accuracy: 60),
            now: now
        )
        XCTAssertTrue(accepted.accepted)

        let outsideTarget = CLLocation(latitude: 26.166250, longitude: 50.543676)
        let rejected = ZoneVerifier().verify(
            zone: .campusAStudent,
            reading: reading(latitude: outsideTarget.coordinate.latitude, longitude: outsideTarget.coordinate.longitude, accuracy: 60),
            now: now
        )
        XCTAssertFalse(rejected.accepted)
        XCTAssertEqual(rejected.failure, .outsideZone)
    }

    func testClearlyOutsideNegativeInaccurateAndStaleReadingsAreRejected() {
        let verifier = ZoneVerifier()
        let outside = verifier.verify(
            zone: .campusAStudent,
            reading: reading(latitude: 26.167000, longitude: 50.543676, accuracy: 5), now: now
        )
        let negative = verifier.verify(
            zone: .campusAStudent,
            reading: reading(latitude: 26.164736, longitude: 50.543676, accuracy: -1), now: now
        )
        let inaccurate = verifier.verify(
            zone: .campusAStudent,
            reading: reading(latitude: 26.164736, longitude: 50.543676, accuracy: 65.1), now: now
        )
        let stale = verifier.verify(
            zone: .campusAStudent,
            reading: LocationReading(
                latitude: 26.164736, longitude: 50.543676,
                horizontalAccuracy: 5, timestamp: now.addingTimeInterval(-16)
            ), now: now
        )

        XCTAssertEqual(outside.failure, .outsideZone)
        XCTAssertEqual(negative.failure, .invalidLocation)
        XCTAssertEqual(inaccurate.failure, .inaccurateLocation)
        XCTAssertEqual(stale.failure, .staleLocation)
    }

    func testUnknownAndInactiveZonesFailSafely() {
        let reading = reading(latitude: 26.164736, longitude: 50.543676, accuracy: 5)
        XCTAssertEqual(ZoneVerifier().verify(zone: nil, reading: reading, now: now).failure, .unknownZone)
        XCTAssertEqual(
            ZoneVerifier().verify(zone: .testZone(radius: 140, isActive: false), reading: reading, now: now).failure,
            .inactiveZone
        )
    }

    func testRepositoryErrorMappingUsesStableServerTokens() {
        XCTAssertEqual(SupabaseParkingSignalRepository.repositoryError(for: "P0001 zone_unavailable"), .zoneUnavailable)
        XCTAssertEqual(SupabaseParkingSignalRepository.repositoryError(for: "22023 location_unavailable"), .locationUnavailable)
        XCTAssertEqual(SupabaseParkingSignalRepository.repositoryError(for: "22023 location_inaccurate"), .locationInaccurate)
        XCTAssertEqual(SupabaseParkingSignalRepository.repositoryError(for: "P0001 outside_parking_zone"), .outsideParkingZone)
        XCTAssertNil(SupabaseParkingSignalRepository.repositoryError(for: "some_other_failure"))
    }

    private func reading(latitude: Double, longitude: Double, accuracy: Double) -> LocationReading {
        LocationReading(
            latitude: latitude, longitude: longitude,
            horizontalAccuracy: accuracy, timestamp: now
        )
    }
}

@MainActor
final class LocationAndPublishStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDeniedAndRestrictedLocationStatesAreExplicit() async {
        for expected in [LocationAuthorizationState.denied, .restricted] {
            let provider = StubLocationProvider(status: expected)
            let store = LocationStore(provider: provider)
            await store.verify(zone: .campusAStudent)

            XCTAssertEqual(store.authorizationState, expected)
            XCTAssertEqual(
                store.verificationState,
                expected == .denied ? .permissionDenied : .restricted
            )
            XCTAssertEqual(provider.locationRequestCount, 0)
        }
    }

    func testPublishEligibilityCoversPermissionLocatingAccuracyOutsideAndValidStates() {
        let vehicleID = UUID()
        let valid = ZoneVerificationResult(
            distanceMeters: 0, horizontalAccuracy: 5, accepted: true, failure: nil
        )

        XCTAssertFalse(eligible(vehicleID, .notRequested))
        XCTAssertFalse(eligible(vehicleID, .permissionDenied))
        XCTAssertFalse(eligible(vehicleID, .locating))
        XCTAssertFalse(eligible(vehicleID, .inaccurate(accuracy: 70)))
        XCTAssertFalse(eligible(vehicleID, .outsideZone(distance: 250, accuracy: 5)))
        XCTAssertFalse(eligible(nil, .verified(valid)))
        XCTAssertFalse(PublishSignalEligibility.canPublish(
            vehicleID: vehicleID, minutes: 3, locationState: .verified(valid), isPublishing: false
        ))
        XCTAssertFalse(PublishSignalEligibility.canPublish(
            vehicleID: vehicleID, minutes: 5, locationState: .verified(valid), isPublishing: true
        ))
        XCTAssertTrue(eligible(vehicleID, .verified(valid)))
    }

    func testLocationStoreClassifiesInaccurateOutsideVerifiedAndUnavailable() async {
        let provider = StubLocationProvider(status: .authorized)
        let store = LocationStore(provider: provider)

        provider.result = .success(reading(latitude: 26.164736, accuracy: 70))
        await store.verify(zone: .campusAStudent)
        XCTAssertEqual(store.verificationState, .inaccurate(accuracy: 70))

        provider.result = .success(reading(latitude: 26.167000, accuracy: 5))
        await store.verify(zone: .campusAStudent)
        guard case .outsideZone = store.verificationState else {
            return XCTFail("Expected outside-zone state")
        }

        provider.result = .success(reading(latitude: 26.164736, accuracy: 5))
        await store.verify(zone: .campusAStudent)
        XCTAssertTrue(store.verificationState.isVerified)

        provider.result = .failure(LocationServiceError.unavailable)
        await store.verify(zone: .campusAStudent)
        XCTAssertEqual(store.verificationState, .unavailable)
    }

    func testDuplicatePublishRequestsAreBlockedAndPayloadIsPreserved() async {
        let userID = UUID()
        let vehicleID = UUID()
        let repository = SuspendedPublishRepository()
        let store = SignalStore(repository: repository, userID: userID)
        let location = reading(latitude: 26.164736, accuracy: 5)

        let first = Task {
            await store.publish(
                zone: .campusAStudent, minutes: 5,
                ownerVehicleID: vehicleID, location: location, now: now
            )
        }
        while repository.publishCount == 0 { await Task.yield() }

        let duplicate = await store.publish(
            zone: .campusAStudent, minutes: 5,
            ownerVehicleID: vehicleID, location: location, now: now
        )
        XCTAssertFalse(duplicate)
        XCTAssertEqual(repository.publishCount, 1)

        repository.resumePublish()
        let firstResult = await first.value
        XCTAssertTrue(firstResult)
        XCTAssertEqual(repository.request?.zoneID, "campus_a_student")
        XCTAssertEqual(repository.request?.ownerVehicleID, vehicleID)
        XCTAssertEqual(repository.request?.location, location)
    }

    private func eligible(_ vehicleID: UUID?, _ state: LocationStore.VerificationState) -> Bool {
        PublishSignalEligibility.canPublish(
            vehicleID: vehicleID, minutes: 5, locationState: state, isPublishing: false
        )
    }

    private func reading(latitude: Double, accuracy: Double) -> LocationReading {
        LocationReading(
            latitude: latitude, longitude: 50.543676,
            horizontalAccuracy: accuracy, timestamp: .now
        )
    }
}

private extension ParkingZone {
    static func testZone(radius: Double, isActive: Bool = true) -> ParkingZone {
        ParkingZone(
            id: "campus_a_student", name: "Campus A Student Car Park", campus: .campusA,
            landmark: "West of the stadium", latitude: 26.164736, longitude: 50.543676,
            verificationRadiusMeters: radius, isActive: isActive,
            createdAt: .distantPast, updatedAt: .distantPast
        )
    }
}

@MainActor
private final class StubLocationProvider: LocationProviding {
    var authorizationStatus: LocationAuthorizationState
    var result: Result<LocationReading, any Error> = .failure(LocationServiceError.unavailable)
    var locationRequestCount = 0

    init(status: LocationAuthorizationState) { authorizationStatus = status }

    func requestWhenInUseAuthorization() async -> LocationAuthorizationState { authorizationStatus }

    func requestLocation() async throws -> LocationReading {
        locationRequestCount += 1
        return try result.get()
    }
}

@MainActor
private final class SuspendedPublishRepository: ParkingSignalRepository {
    var publishCount = 0
    var request: PublishParkingSignalRequest?
    private var continuation: CheckedContinuation<Void, Never>?

    func fetchFeed(now: Date) async throws -> SignalFeed {
        SignalFeed(signals: request.map { [$0.signal] } ?? [], handoverDetails: [:])
    }

    func publish(_ request: PublishParkingSignalRequest) async throws -> ParkingSignal {
        publishCount += 1
        self.request = request
        await withCheckedContinuation { continuation = $0 }
        return request.signal
    }

    func resumePublish() {
        continuation?.resume()
        continuation = nil
    }

    func claim(signalID: UUID, claimantVehicleID: UUID) async throws -> ParkingSignal { throw ParkingSignalRepositoryError.transitionUnavailable }
    func markArrived(signalID: UUID) async throws -> ParkingSignal { throw ParkingSignalRepositoryError.transitionUnavailable }
    func releaseClaim(signalID: UUID) async throws -> ParkingSignal { throw ParkingSignalRepositoryError.transitionUnavailable }
    func cancel(signalID: UUID) async throws -> ParkingSignal { throw ParkingSignalRepositoryError.transitionUnavailable }
    func markVacated(signalID: UUID) async throws -> ParkingSignal { throw ParkingSignalRepositoryError.transitionUnavailable }
    func complete(signalID: UUID) async throws -> ParkingSignal { throw ParkingSignalRepositoryError.transitionUnavailable }
    func markUnavailable(signalID: UUID) async throws -> ParkingSignal { throw ParkingSignalRepositoryError.transitionUnavailable }
    func observe(_ receive: @escaping @MainActor (SignalEvent) async -> Void) async throws {}
}
