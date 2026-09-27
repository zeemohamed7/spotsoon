import XCTest
@testable import SpotSoon

final class ApproachTrackingModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testApproachLocationDecodesPrivateDatabaseColumns() throws {
        let signalID = UUID()
        let json = """
        {
          "signal_id":"\(signalID.uuidString)",
          "owner_latitude":26.164736,
          "owner_longitude":50.543676,
          "owner_horizontal_accuracy":8,
          "owner_captured_at":"2027-01-15T08:00:00Z",
          "claimant_latitude":26.164900,
          "claimant_longitude":50.543700,
          "claimant_horizontal_accuracy":12,
          "claimant_captured_at":"2027-01-15T08:00:05Z",
          "claimant_sharing_enabled":true,
          "updated_at":"2027-01-15T08:00:05Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let location = try decoder.decode(ApproachLocation.self, from: json)

        XCTAssertEqual(location.signalID, signalID)
        XCTAssertEqual(location.owner.horizontalAccuracy, 8)
        XCTAssertEqual(location.claimant?.latitude, 26.164900)
        XCTAssertTrue(location.claimantSharingEnabled)
    }

    func testMalformedOrIncompleteCoordinatesAreRejected() {
        let invalidRange = json(ownerLatitude: 91, claimantLatitude: nil)
        XCTAssertThrowsError(try decoder.decode(ApproachLocation.self, from: invalidRange))

        let incomplete = json(ownerLatitude: 26, claimantLatitude: 26.1)
        XCTAssertThrowsError(try decoder.decode(ApproachLocation.self, from: incomplete))
    }

    func testDistanceBandsUseSpecifiedBoundaries() {
        XCTAssertEqual(ApproachBand(distance: 151), .onTheWay)
        XCTAssertEqual(ApproachBand(distance: 150), .approaching)
        XCTAssertEqual(ApproachBand(distance: 50), .approaching)
        XCTAssertEqual(ApproachBand(distance: 49.9), .nearby)
        XCTAssertEqual(ApproachBand(distance: 25), .nearby)
        XCTAssertEqual(ApproachBand(distance: 24.9), .veryClose)
    }

    func testFreshnessIsActiveThroughFifteenSecondsThenStale() {
        let point = ApproachPoint(latitude: 26, longitude: 50, horizontalAccuracy: 5, capturedAt: now)
        let location = ApproachLocation(
            signalID: UUID(), owner: point, claimant: point,
            claimantSharingEnabled: true, updatedAt: now
        )
        XCTAssertEqual(ApproachFreshness.evaluate(location: location, now: now.addingTimeInterval(15)), .active(seconds: 15))
        XCTAssertEqual(ApproachFreshness.evaluate(location: location, now: now.addingTimeInterval(16)), .stale(seconds: 16))
        XCTAssertEqual(
            ApproachFreshness.evaluate(
                location: ApproachLocation(
                    signalID: location.signalID, owner: point, claimant: point,
                    claimantSharingEnabled: false, updatedAt: now
                ), now: now
            ),
            .paused
        )
    }

    func testReadingValidationRejectsStaleAndInaccurateData() {
        XCTAssertTrue(ApproachReadingPolicy.accepts(reading(at: now, accuracy: 65), now: now.addingTimeInterval(15)))
        XCTAssertFalse(ApproachReadingPolicy.accepts(reading(at: now, accuracy: 65.1), now: now))
        XCTAssertFalse(ApproachReadingPolicy.accepts(reading(at: now, accuracy: 5), now: now.addingTimeInterval(16)))
    }

    func testUploadCadenceAcceptsFiveSecondsOrFifteenMetres() {
        let previous = ApproachPoint(latitude: 26, longitude: 50, horizontalAccuracy: 5, capturedAt: now)
        XCTAssertFalse(ApproachReadingPolicy.shouldUpload(
            reading(at: now.addingTimeInterval(4), accuracy: 5), after: previous,
            now: now.addingTimeInterval(4), distanceCalculator: FixedDistance(value: 14)
        ))
        XCTAssertTrue(ApproachReadingPolicy.shouldUpload(
            reading(at: now.addingTimeInterval(5), accuracy: 5), after: previous,
            now: now.addingTimeInterval(5), distanceCalculator: FixedDistance(value: 0)
        ))
        XCTAssertTrue(ApproachReadingPolicy.shouldUpload(
            reading(at: now.addingTimeInterval(1), accuracy: 5), after: previous,
            now: now.addingTimeInterval(1), distanceCalculator: FixedDistance(value: 15)
        ))
    }

    func testRepositoryErrorMappingIsStableAndSafe() {
        XCTAssertEqual(
            SupabaseApproachTrackingRepository.repositoryError(for: "42501 authentication_required"),
            .authenticationRequired
        )
        XCTAssertEqual(
            SupabaseApproachTrackingRepository.repositoryError(for: "P0001 approach_unavailable"),
            .unavailable
        )
        XCTAssertEqual(
            SupabaseApproachTrackingRepository.repositoryError(for: "PGRST202 set_approach_location_sharing missing"),
            .databaseSetupRequired
        )
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func json(ownerLatitude: Double, claimantLatitude: Double?) -> Data {
        let claimant = claimantLatitude.map { "\"claimant_latitude\":\($0)," } ?? ""
        return """
        {
          "signal_id":"\(UUID().uuidString)",
          "owner_latitude":\(ownerLatitude),
          "owner_longitude":50,
          "owner_horizontal_accuracy":5,
          "owner_captured_at":"2027-01-15T08:00:00Z",
          \(claimant)
          "claimant_sharing_enabled":false,
          "updated_at":"2027-01-15T08:00:00Z"
        }
        """.data(using: .utf8)!
    }

    private func reading(at date: Date, accuracy: Double) -> LocationReading {
        LocationReading(latitude: 26, longitude: 50, horizontalAccuracy: accuracy, timestamp: date)
    }
}

@MainActor
final class ApproachTrackingStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testClaimantMustExplicitlyEnableAndDuplicateEnableIsIgnored() async {
        let repository = ApproachRepositorySpy(location: location(sharing: false))
        let provider = ApproachProviderStub(status: .authorized, reading: reading())
        let store = ApproachTrackingStore(
            repository: repository, provider: provider, signalID: repository.location.signalID,
            isClaimant: true, clock: FixedApproachClock(now: now)
        )

        await store.enableSharing()
        await store.enableSharing()

        XCTAssertTrue(store.isSharing)
        XCTAssertEqual(repository.sharingCalls, [true])
        XCTAssertEqual(repository.updateCount, 1)
    }

    func testPauseStopsUploadsAndClearsServerSharingFlag() async {
        let repository = ApproachRepositorySpy(location: location(sharing: false))
        let store = ApproachTrackingStore(
            repository: repository,
            provider: ApproachProviderStub(status: .authorized, reading: reading()),
            signalID: repository.location.signalID, isClaimant: true,
            clock: FixedApproachClock(now: now)
        )
        await store.enableSharing()
        await store.pauseSharing()
        await store.captureAndUpload()

        XCTAssertFalse(store.isSharing)
        XCTAssertEqual(repository.sharingCalls, [true, false])
        XCTAssertEqual(repository.updateCount, 1)
    }

    func testRestorationForcesSharingOffAndDoesNotResume() async {
        let repository = ApproachRepositorySpy(location: location(sharing: true))
        let store = ApproachTrackingStore(
            repository: repository,
            provider: ApproachProviderStub(status: .authorized, reading: reading()),
            signalID: repository.location.signalID, isClaimant: true,
            clock: FixedApproachClock(now: now)
        )

        await store.start()
        await store.stop()

        XCTAssertFalse(store.isSharing)
        XCTAssertEqual(repository.sharingCalls, [false])
        XCTAssertEqual(repository.updateCount, 0)
    }

    func testOwnerCanPollButCannotEnableClaimantSharing() async {
        let repository = ApproachRepositorySpy(location: location(sharing: true))
        let store = ApproachTrackingStore(
            repository: repository,
            provider: ApproachProviderStub(status: .authorized, reading: reading()),
            signalID: repository.location.signalID, isClaimant: false,
            clock: FixedApproachClock(now: now)
        )
        await store.refresh()
        await store.enableSharing()

        XCTAssertNotNil(store.location)
        XCTAssertTrue(repository.sharingCalls.isEmpty)
        XCTAssertEqual(repository.updateCount, 0)
    }

    func testRejectedUpdateStopsLocalSharingImmediately() async {
        let repository = ApproachRepositorySpy(location: location(sharing: false))
        repository.updateError = ApproachTrackingRepositoryError.authenticationRequired
        let store = ApproachTrackingStore(
            repository: repository,
            provider: ApproachProviderStub(status: .authorized, reading: reading()),
            signalID: repository.location.signalID, isClaimant: true,
            clock: FixedApproachClock(now: now)
        )

        await store.enableSharing()

        XCTAssertFalse(store.isSharing)
        XCTAssertEqual(
            store.errorMessage,
            "Your private session ended. Reopen SpotSoon to continue."
        )
    }

    private func reading() -> LocationReading {
        LocationReading(latitude: 26.1648, longitude: 50.5437, horizontalAccuracy: 7, timestamp: now)
    }

    private func location(sharing: Bool) -> ApproachLocation {
        ApproachLocation(
            signalID: UUID(),
            owner: ApproachPoint(latitude: 26.1647, longitude: 50.5436, horizontalAccuracy: 6, capturedAt: now),
            claimant: nil, claimantSharingEnabled: sharing, updatedAt: now
        )
    }
}

private struct FixedDistance: ApproachDistanceCalculating {
    let value: Double
    func distance(from: ApproachPoint, to: ApproachPoint) -> Double { value }
}

private struct FixedApproachClock: ApproachClock {
    let now: Date
    func sleep(seconds: TimeInterval) async throws { throw CancellationError() }
}

@MainActor
private final class ApproachProviderStub: ApproachLocationProviding {
    var status: LocationAuthorizationState
    let reading: LocationReading
    init(status: LocationAuthorizationState, reading: LocationReading) {
        self.status = status
        self.reading = reading
    }
    var approachAuthorizationStatus: LocationAuthorizationState { status }
    func requestApproachAuthorization() async -> LocationAuthorizationState {
        status = .authorized
        return status
    }
    func requestApproachLocation() async throws -> LocationReading { reading }
    func openApproachSettings() {}
}

@MainActor
private final class ApproachRepositorySpy: ApproachTrackingRepository {
    var location: ApproachLocation
    var sharingCalls: [Bool] = []
    var updateCount = 0
    var updateError: Error?

    init(location: ApproachLocation) { self.location = location }

    func fetch(signalID: UUID) async throws -> ApproachLocation? { location }

    func setSharing(signalID: UUID, enabled: Bool) async throws -> ApproachLocation {
        sharingCalls.append(enabled)
        location = ApproachLocation(
            signalID: location.signalID, owner: location.owner, claimant: location.claimant,
            claimantSharingEnabled: enabled, updatedAt: location.updatedAt
        )
        return location
    }

    func update(signalID: UUID, reading: LocationReading) async throws -> ApproachLocation {
        updateCount += 1
        if let updateError { throw updateError }
        location = ApproachLocation(
            signalID: location.signalID, owner: location.owner,
            claimant: ApproachPoint(
                latitude: reading.latitude, longitude: reading.longitude,
                horizontalAccuracy: reading.horizontalAccuracy, capturedAt: reading.timestamp
            ),
            claimantSharingEnabled: true, updatedAt: reading.timestamp
        )
        return location
    }
}
