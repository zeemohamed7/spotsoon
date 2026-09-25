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

    func testCampusBZoneDecodesDatabaseColumns() throws {
        let data = """
        {
          "id":"campus_b_student",
          "name":"Campus B Student Car Park",
          "campus":"campus_b",
          "landmark":"Beside Building 20",
          "latitude":26.158319,
          "longitude":50.546641,
          "verification_radius_meters":90,
          "is_active":true,
          "created_at":"2026-09-25T12:00:00Z",
          "updated_at":"2026-09-25T12:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let zone = try decoder.decode(ParkingZone.self, from: data)

        XCTAssertEqual(zone, ParkingZone.campusBStudent.withDates(zone.createdAt, zone.updatedAt))
        XCTAssertEqual(zone.alternativeContext, "formerly BTI")
        XCTAssertTrue(zone.isSupported)
    }

    func testCommittedCampusAAndCampusBDefinitionsRemainExact() {
        XCTAssertEqual(ParkingZone.campusAStudent.latitude, 26.164736)
        XCTAssertEqual(ParkingZone.campusAStudent.longitude, 50.543676)
        XCTAssertEqual(ParkingZone.campusAStudent.verificationRadiusMeters, 140)
        XCTAssertEqual(ParkingZone.campusBStudent.latitude, 26.158319)
        XCTAssertEqual(ParkingZone.campusBStudent.longitude, 50.546641)
        XCTAssertEqual(ParkingZone.campusBStudent.verificationRadiusMeters, 90)
    }

    func testCampusBCentreInsideAndOutsideRespectNinetyMetreRadius() {
        let verifier = ZoneVerifier()
        let centre = verifier.verify(
            zone: .campusBStudent,
            reading: reading(latitude: 26.158319, longitude: 50.546641, accuracy: 5), now: now
        )
        let inside = verifier.verify(
            zone: .campusBStudent,
            reading: reading(latitude: 26.158800, longitude: 50.546641, accuracy: 5), now: now
        )
        let outside = verifier.verify(
            zone: .campusBStudent,
            reading: reading(latitude: 26.159500, longitude: 50.546641, accuracy: 5), now: now
        )

        XCTAssertTrue(centre.accepted)
        XCTAssertEqual(centre.distanceMeters ?? -1, 0, accuracy: 0.01)
        XCTAssertTrue(inside.accepted)
        XCTAssertLessThan(inside.distanceMeters ?? .infinity, 90)
        XCTAssertFalse(outside.accepted)
        XCTAssertEqual(outside.failure, .outsideZone)
        XCTAssertGreaterThan(outside.distanceMeters ?? 0, 90 + 5)
    }

    func testNearestZoneSuggestionWorksInBothDirections() {
        let verifier = ZoneVerifier()
        let atCampusB = reading(latitude: 26.158319, longitude: 50.546641, accuracy: 5)
        let atCampusA = reading(latitude: 26.164736, longitude: 50.543676, accuracy: 5)

        XCTAssertEqual(
            verifier.suggestedAlternative(
                to: .campusAStudent, among: ParkingZone.supportedDefaults,
                reading: atCampusB, now: now
            )?.id,
            ParkingZone.campusBStudent.id
        )
        XCTAssertEqual(
            verifier.suggestedAlternative(
                to: .campusBStudent, among: ParkingZone.supportedDefaults,
                reading: atCampusA, now: now
            )?.id,
            ParkingZone.campusAStudent.id
        )
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

    func testWrongZoneSuggestionAndExplicitSwitchRerunVerification() async {
        let provider = StubLocationProvider(status: .authorized)
        provider.result = .success(LocationReading(
            latitude: ParkingZone.campusBStudent.latitude,
            longitude: ParkingZone.campusBStudent.longitude,
            horizontalAccuracy: 5,
            timestamp: .now
        ))
        let store = LocationStore(provider: provider)

        await store.verify(zone: .campusAStudent, availableZones: ParkingZone.supportedDefaults)
        XCTAssertEqual(store.suggestedZoneID, ParkingZone.campusBStudent.id)
        XCTAssertEqual(store.verificationZoneID, ParkingZone.campusAStudent.id)
        XCTAssertFalse(store.verificationState.isVerified)

        await store.switchAndVerify(
            to: .campusBStudent,
            availableZones: ParkingZone.supportedDefaults
        )
        XCTAssertNil(store.suggestedZoneID)
        XCTAssertEqual(store.verificationZoneID, ParkingZone.campusBStudent.id)
        XCTAssertTrue(store.verificationState.isVerified)
        XCTAssertEqual(provider.locationRequestCount, 2)
    }

    func testChangingZonesInvalidatesPreviousVerification() async {
        let provider = StubLocationProvider(status: .authorized)
        provider.result = .success(reading(latitude: 26.164736, accuracy: 5))
        let store = LocationStore(provider: provider)
        await store.verify(zone: .campusAStudent, availableZones: ParkingZone.supportedDefaults)
        XCTAssertTrue(store.isVerified(for: ParkingZone.campusAStudent.id))

        store.invalidateVerification()

        XCTAssertEqual(store.verificationState, .notRequested)
        XCTAssertNil(store.verificationZoneID)
        XCTAssertNil(store.latestReading)
        XCTAssertFalse(store.isVerified(for: ParkingZone.campusBStudent.id))
    }

    func testCampusALocationSuggestsSwitchWhenCampusBIsSelected() async {
        let provider = StubLocationProvider(status: .authorized)
        provider.result = .success(reading(latitude: 26.164736, accuracy: 5))
        let store = LocationStore(provider: provider)

        await store.verify(zone: .campusBStudent, availableZones: ParkingZone.supportedDefaults)

        XCTAssertEqual(store.verificationZoneID, ParkingZone.campusBStudent.id)
        XCTAssertEqual(store.suggestedZoneID, ParkingZone.campusAStudent.id)
        XCTAssertFalse(store.verificationState.isVerified)
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

    func testSelectedCampusBZoneIDAndLocationReachRepository() async {
        let repository = SuspendedPublishRepository()
        let store = SignalStore(repository: repository, userID: UUID())
        let vehicleID = UUID()
        let location = LocationReading(
            latitude: ParkingZone.campusBStudent.latitude,
            longitude: ParkingZone.campusBStudent.longitude,
            horizontalAccuracy: 6,
            timestamp: .now
        )
        let task = Task {
            await store.publish(
                zone: .campusBStudent, minutes: 2,
                ownerVehicleID: vehicleID, location: location, now: now
            )
        }
        while repository.publishCount == 0 { await Task.yield() }
        repository.resumePublish()

        let published = await task.value
        XCTAssertTrue(published)
        XCTAssertEqual(repository.request?.zoneID, ParkingZone.campusBStudent.id)
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

@MainActor
final class ParkingZoneStoreTests: XCTestCase {
    func testSelectingEitherZonePersistsAndRestoresSelection() async {
        let persistence = MemoryZoneSelection()
        let repository = StubZoneRepository(zones: ParkingZone.supportedDefaults)
        let store = ParkingZoneStore(repository: repository, selectionPersistence: persistence)
        await store.load()
        XCTAssertEqual(store.selectedZoneID, ParkingZone.campusAStudent.id)

        XCTAssertTrue(store.selectZone(id: ParkingZone.campusBStudent.id))
        XCTAssertEqual(persistence.selectedZoneID, ParkingZone.campusBStudent.id)

        let restored = ParkingZoneStore(repository: repository, selectionPersistence: persistence)
        await restored.load()
        XCTAssertEqual(restored.selectedZoneID, ParkingZone.campusBStudent.id)
        XCTAssertEqual(restored.selectedZone?.landmark, "Beside Building 20")
    }

    func testInvalidPersistedZoneFallsBackToFirstSupportedActiveZone() async {
        let persistence = MemoryZoneSelection(selectedZoneID: "faculty_only")
        let inactiveB = ParkingZone.campusBStudent.withActive(false)
        let store = ParkingZoneStore(
            repository: StubZoneRepository(zones: [inactiveB, .campusAStudent]),
            selectionPersistence: persistence
        )

        await store.load()

        XCTAssertEqual(store.zones.map(\.id), [ParkingZone.campusAStudent.id])
        XCTAssertEqual(store.selectedZoneID, ParkingZone.campusAStudent.id)
        XCTAssertEqual(persistence.selectedZoneID, ParkingZone.campusAStudent.id)
        XCTAssertFalse(store.selectZone(id: inactiveB.id))
    }

    func testSignalsFilterByExactSelectedZoneWithoutDiscardingOtherZone() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = ParkingSignal.testSignal(zone: .campusAStudent, now: now)
        let b = ParkingSignal.testSignal(zone: .campusBStudent, now: now)
        let all = ParkingSignal.visible([b, a], at: now)

        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(ParkingSignal.visible(all, in: .campusAStudent, at: now).map(\.id), [a.id])
        XCTAssertEqual(ParkingSignal.visible(all, in: .campusBStudent, at: now).map(\.id), [b.id])
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

    func withDates(_ createdAt: Date, _ updatedAt: Date) -> ParkingZone {
        ParkingZone(
            id: id, name: name, campus: campus, landmark: landmark,
            latitude: latitude, longitude: longitude,
            verificationRadiusMeters: verificationRadiusMeters, isActive: isActive,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }

    func withActive(_ isActive: Bool) -> ParkingZone {
        ParkingZone(
            id: id, name: name, campus: campus, landmark: landmark,
            latitude: latitude, longitude: longitude,
            verificationRadiusMeters: verificationRadiusMeters, isActive: isActive,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

private extension ParkingSignal {
    static func testSignal(zone: ParkingZone, now: Date) -> ParkingSignal {
        ParkingSignal(
            id: UUID(), createdBy: UUID(), zoneID: zone.id,
            campus: zone.campus, zone: zone.name,
            leavingAt: now.addingTimeInterval(120),
            expiresAt: now.addingTimeInterval(420),
            status: .active, createdAt: now
        )
    }
}

@MainActor
private final class StubZoneRepository: ParkingZoneRepository {
    let zones: [ParkingZone]
    init(zones: [ParkingZone]) { self.zones = zones }
    func fetchActiveZones() async throws -> [ParkingZone] { zones }
}

@MainActor
private final class MemoryZoneSelection: ParkingZoneSelectionPersisting {
    var selectedZoneID: String?
    init(selectedZoneID: String? = nil) { self.selectedZoneID = selectedZoneID }
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
