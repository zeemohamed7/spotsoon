import XCTest
@testable import SpotSoon

@MainActor
final class SignalStoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFiltersInactiveAndExpiredAndSortsChronologically() async {
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
        XCTAssertEqual(ParkingSignal.active([row], at: now).count, 1)
        XCTAssertTrue(ParkingSignal.active([row], at: now.addingTimeInterval(420)).isEmpty)
    }

    private func signal(leaving: Double, expiry: Double, status: ParkingSignal.Status = .active) -> ParkingSignal {
        ParkingSignal(id: UUID(), createdBy: UUID(), campus: .campusA, zone: "A1",
                      leavingAt: now.addingTimeInterval(leaving), expiresAt: now.addingTimeInterval(expiry),
                      status: status, createdAt: now)
    }
}

@MainActor
private final class FakeRepository: ParkingSignalRepository {
    var rows: [ParkingSignal] = []
    var inserted: ParkingSignal?
    var shouldFail = false
    struct Failure: Error {}
    func fetchActive(now: Date) async throws -> [ParkingSignal] {
        if shouldFail { throw Failure() }
        return rows
    }
    func insert(_ signal: ParkingSignal) async throws {
        if shouldFail { throw Failure() }
        inserted = signal
    }
    func observe(_ receive: @escaping @MainActor (SignalEvent) async -> Void) async throws {}
}
