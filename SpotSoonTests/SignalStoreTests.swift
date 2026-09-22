import XCTest
@testable import SpotSoon

@MainActor
final class SignalStoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFiltersInvisibleAndExpiredAndSortsChronologically() async {
        let repo = FakeRepository()
        let early = signal(leaving: 120, expiry: 420)
        let later = signal(leaving: 600, expiry: 900)
        let leavingPassed = signal(leaving: -60, expiry: 240)
        repo.rows = [later, signal(leaving: 0, expiry: 0), early,
                     signal(leaving: 0, expiry: -1), signal(leaving: 0, expiry: 600, status: .cancelled),
                     signal(leaving: 0, expiry: 600, status: .expired), leavingPassed]
        let store = SignalStore(repository: repo, userID: UUID())
        await store.refresh(now: now)
        XCTAssertEqual(store.signals.map(\.id), [leavingPassed.id, early.id, later.id])
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.listError)
    }

    func testLeavingAndExpiryForEveryDurationAndAuthenticatedOwner() async {
        for minutes in [2, 5, 10] {
            let repo = FakeRepository()
            let owner = UUID()
            let store = SignalStore(repository: repo, userID: owner)
            let success = await store.publish(campus: .campusB, zone: "B2", minutes: minutes, now: now)
            XCTAssertTrue(success)
            let row = try! XCTUnwrap(repo.inserted)
            XCTAssertEqual(row.createdBy, owner)
            XCTAssertEqual(row.leavingAt, now.addingTimeInterval(Double(minutes * 60)))
            XCTAssertEqual(row.expiresAt, row.leavingAt.addingTimeInterval(300))
            XCTAssertEqual(row.createdAt, now)
            XCTAssertEqual(row.status, .active)
        }
    }

    func testFailedInsertRemainsVisibleAndDoesNotReportSuccess() async {
        let repo = FakeRepository()
        repo.shouldFail = true
        let store = SignalStore(repository: repo, userID: UUID())
        let success = await store.publish(campus: .campusA, zone: "A1", minutes: 2, now: now)
        XCTAssertFalse(success)
        XCTAssertNotNil(store.publishError)
        XCTAssertFalse(store.isPublishing)
    }

    func testFetchFailureIsVisible() async {
        let repo = FakeRepository()
        repo.shouldFail = true
        let store = SignalStore(repository: repo, userID: UUID())
        await store.refresh(now: now)
        XCTAssertNotNil(store.listError)
        XCTAssertFalse(store.isLoading)
    }

    func testExpiryWithoutDatabaseEvent() {
        let row = signal(leaving: 120, expiry: 420)
        XCTAssertEqual(ParkingSignal.visible([row], at: now).count, 1)
        XCTAssertTrue(ParkingSignal.visible([row], at: now.addingTimeInterval(420)).isEmpty)
    }

    func testOwnerCannotClaimActiveSignal() {
        let owner = UUID()
        let row = signal(owner: owner)
        let presentation = row.claimPresentation(for: owner)
        XCTAssertEqual(presentation, .yourSignal)
        XCTAssertFalse(presentation.canClaim)
    }

    func testAnotherUserCanClaimActiveSignal() {
        let row = signal(owner: UUID())
        let presentation = row.claimPresentation(for: UUID())
        XCTAssertEqual(presentation, .available)
        XCTAssertTrue(presentation.canClaim)
    }

    func testClaimantReceivesYoureHeadingThere() {
        let claimant = UUID()
        let row = signal(owner: UUID(), status: .claimed, claimedBy: claimant)
        XCTAssertEqual(row.claimPresentation(for: claimant), .youreHeadingThere)
    }

    func testOwnerReceivesSomeoneIsHeadingThere() {
        let owner = UUID()
        let row = signal(owner: owner, status: .claimed, claimedBy: UUID())
        XCTAssertEqual(row.claimPresentation(for: owner), .someoneHeadingThere)
    }

    func testThirdUserSeesClaimed() {
        let row = signal(owner: UUID(), status: .claimed, claimedBy: UUID())
        XCTAssertEqual(row.claimPresentation(for: UUID()), .claimed)
        XCTAssertFalse(row.claimPresentation(for: UUID()).canClaim)
    }

    func testClaimedNonExpiredSignalsRemainVisible() {
        let claimed = signal(expiry: 300, status: .claimed, claimedBy: UUID())
        XCTAssertEqual(ParkingSignal.visible([claimed], at: now), [claimed])
    }

    func testExpiredClaimedSignalsRemainHidden() {
        let claimed = signal(expiry: 0, status: .claimed, claimedBy: UUID())
        XCTAssertTrue(ParkingSignal.visible([claimed], at: now).isEmpty)
    }

    func testRepeatedClaimTapsStartOnlyOneRequest() async {
        let claimant = UUID()
        let active = signal(owner: UUID())
        let claimed = signal(id: active.id, owner: active.createdBy, status: .claimed, claimedBy: claimant)
        let repo = FakeRepository()
        repo.claimResult = claimed
        repo.suspendClaim = true
        let store = SignalStore(repository: repo, userID: claimant)

        let firstClaim = Task { await store.claim(active, now: now) }
        for _ in 0..<100 {
            if repo.claimCallCount > 0 { break }
            await Task.yield()
        }

        XCTAssertTrue(store.isClaiming(active.id))
        let duplicateSucceeded = await store.claim(active, now: now)
        XCTAssertFalse(duplicateSucceeded)
        XCTAssertEqual(repo.claimCallCount, 1)

        repo.finishSuspendedClaim()
        let firstSucceeded = await firstClaim.value
        XCTAssertTrue(firstSucceeded)
        XCTAssertFalse(store.isClaiming(active.id))
        XCTAssertEqual(store.signals.first, claimed)
    }

    func testSignalUnavailableBecomesClearErrorAndRefreshes() async {
        let active = signal(owner: UUID())
        let repo = FakeRepository()
        repo.rows = [active]
        repo.claimError = ParkingSignalRepositoryError.signalUnavailable
        let store = SignalStore(repository: repo, userID: UUID())

        let succeeded = await store.claim(active, now: now)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            store.claimErrors[active.id],
            "This signal was already claimed or is no longer available."
        )
        XCTAssertEqual(repo.claimCallCount, 1)
        XCTAssertEqual(repo.fetchCallCount, 1)
    }

    func testOwnerClaimIsRejectedBeforeRepositoryCall() async {
        let owner = UUID()
        let active = signal(owner: owner)
        let repo = FakeRepository()
        let store = SignalStore(repository: repo, userID: owner)

        let succeeded = await store.claim(active, now: now)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(repo.claimCallCount, 0)
    }

    private func signal(
        id: UUID = UUID(),
        owner: UUID = UUID(),
        leaving: Double = 120,
        expiry: Double = 420,
        status: ParkingSignal.Status = .active,
        claimedBy: UUID? = nil
    ) -> ParkingSignal {
        ParkingSignal(id: id, createdBy: owner, campus: .campusA, zone: "A1",
                      leavingAt: now.addingTimeInterval(leaving), expiresAt: now.addingTimeInterval(expiry),
                      status: status, createdAt: now, claimedBy: claimedBy,
                      claimedAt: claimedBy.map { _ in now })
    }
}

@MainActor
private final class FakeRepository: ParkingSignalRepository {
    var rows: [ParkingSignal] = []
    var inserted: ParkingSignal?
    var shouldFail = false
    var claimResult: ParkingSignal?
    var claimError: (any Error)?
    var suspendClaim = false
    var claimCallCount = 0
    var fetchCallCount = 0
    private var claimContinuation: CheckedContinuation<ParkingSignal, any Error>?
    struct Failure: Error {}
    func fetchActive(now: Date) async throws -> [ParkingSignal] {
        fetchCallCount += 1
        if shouldFail { throw Failure() }
        return rows
    }
    func insert(_ signal: ParkingSignal) async throws {
        if shouldFail { throw Failure() }
        inserted = signal
    }
    func claim(signalID: UUID) async throws -> ParkingSignal {
        claimCallCount += 1
        if let claimError { throw claimError }
        guard let claimResult else { throw Failure() }
        if suspendClaim {
            return try await withCheckedThrowingContinuation { continuation in
                claimContinuation = continuation
            }
        }
        return claimResult
    }
    func finishSuspendedClaim() {
        guard let claimResult else { return }
        claimContinuation?.resume(returning: claimResult)
        claimContinuation = nil
    }
    func observe(_ receive: @escaping @MainActor (SignalEvent) async -> Void) async throws {}
}
