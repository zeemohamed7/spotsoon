import XCTest
@testable import SpotSoon

@MainActor
final class VehicleTests: XCTestCase {
    private let userID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDecodingAndUnknownVehicleTypeFallback() throws {
        let json = """
        {
          "id":"20000000-0000-0000-0000-000000000001",
          "user_id":"10000000-0000-0000-0000-000000000001",
          "nickname":"My K5",
          "color":"Midnight grey",
          "vehicle_type":"coupe",
          "make":"Kia",
          "model":"K5",
          "plate_suffix":"404",
          "is_current":true,
          "created_at":"2027-01-15T08:00:00Z",
          "updated_at":"2027-01-15T08:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let vehicle = try decoder.decode(Vehicle.self, from: Data(json.utf8))

        XCTAssertEqual(vehicle.vehicleType, .other)
        XCTAssertEqual(vehicle.summary, "Midnight grey Kia K5 Other · Plate ending 404")
    }

    func testWhitespaceRequiredFieldsPlateAndLengthValidation() throws {
        var draft = VehicleDraft()
        draft.nickname = "   "
        draft.color = "Midnight grey"
        XCTAssertThrowsError(try draft.validated())

        draft.nickname = " My K5 "
        draft.color = "   "
        XCTAssertThrowsError(try draft.validated())

        draft.color = " Midnight grey "
        for invalid in ["A-1", "1234", "🚙"] {
            draft.plateSuffix = invalid
            XCTAssertThrowsError(try draft.validated())
        }
        draft.plateSuffix = " 404 "
        let value = try draft.validated()
        XCTAssertEqual(value.nickname, "My K5")
        XCTAssertEqual(value.color, "Midnight grey")
        XCTAssertEqual(value.plateSuffix, "404")
    }

    func testAddEditSelectAndDeleteCurrentVehicle() async throws {
        let repository = VehicleRepositoryDouble(now: now)
        let store = VehicleStore(repository: repository, userID: userID)

        let addedKia = await store.save(kiaDraft())
        XCTAssertTrue(addedKia)
        let kia = try XCTUnwrap(store.currentVehicle)
        XCTAssertEqual(kia.summary, "Midnight grey Kia K5 Sedan · Plate ending 404")

        var suvDraft = VehicleDraft()
        suvDraft.nickname = "Weekend SUV"
        suvDraft.color = "Blue"
        suvDraft.vehicleType = .suv
        suvDraft.make = "Nissan"
        suvDraft.model = "X-Trail"
        let addedSUV = await store.save(suvDraft)
        XCTAssertTrue(addedSUV)
        let suv = try XCTUnwrap(store.vehicles.first { $0.nickname == "Weekend SUV" })
        XCTAssertEqual(store.currentVehicle?.id, kia.id)

        let selectedSUV = await store.select(suv)
        XCTAssertTrue(selectedSUV)
        XCTAssertEqual(store.currentVehicle?.id, suv.id)
        XCTAssertEqual(store.vehicles.filter(\.isCurrent).count, 1)

        var edited = VehicleDraft(vehicle: suv)
        edited.color = "Deep blue"
        let editedSUV = await store.save(edited, editing: suv)
        XCTAssertTrue(editedSUV)
        XCTAssertEqual(store.currentVehicle?.color, "Deep blue")

        let selected = try XCTUnwrap(store.currentVehicle)
        let deletedSelected = await store.delete(selected)
        XCTAssertTrue(deletedSelected)
        XCTAssertEqual(store.currentVehicle?.id, kia.id)
        XCTAssertEqual(store.vehicles.filter(\.isCurrent).count, 1)
    }

    func testDuplicateSelectionIsBlockedWhileRequestRuns() async throws {
        let first = vehicle(id: UUID(), nickname: "My K5", current: true)
        let second = vehicle(id: UUID(), nickname: "Campus SUV", current: false)
        let repository = VehicleRepositoryDouble(now: now, vehicles: [first, second])
        repository.suspendSetCurrent = true
        let store = VehicleStore(repository: repository, userID: userID)
        await store.load()

        let request = Task { await store.select(second) }
        await waitUntil { repository.setCurrentCalls == 1 }
        let duplicate = await store.select(second)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(repository.setCurrentCalls, 1)
        repository.resumeSetCurrent()
        let selected = await request.value
        XCTAssertTrue(selected)
    }

    func testDuplicateSaveAndDeleteRequestsAreBlocked() async throws {
        let repository = VehicleRepositoryDouble(now: now)
        let store = VehicleStore(repository: repository, userID: userID)
        repository.suspendCreate = true

        let firstSave = Task { await store.save(kiaDraft()) }
        await waitUntil { repository.createCalls == 1 }
        let duplicateSave = await store.save(kiaDraft())
        XCTAssertFalse(duplicateSave)
        XCTAssertEqual(repository.createCalls, 1)
        repository.resumeCreate()
        let firstSaveSucceeded = await firstSave.value
        XCTAssertTrue(firstSaveSucceeded)

        let saved = try XCTUnwrap(store.vehicles.first)
        repository.suspendDelete = true
        let firstDelete = Task { await store.delete(saved) }
        await waitUntil { repository.deleteCalls == 1 }
        let duplicateDelete = await store.delete(saved)
        XCTAssertFalse(duplicateDelete)
        XCTAssertEqual(repository.deleteCalls, 1)
        repository.resumeDelete()
        let firstDeleteSucceeded = await firstDelete.value
        XCTAssertTrue(firstDeleteSucceeded)
    }

    func testFailedEditRollsBackThenRefreshesServerState() async throws {
        let original = vehicle(id: UUID(), nickname: "My K5", current: true)
        let repository = VehicleRepositoryDouble(now: now, vehicles: [original])
        let store = VehicleStore(repository: repository, userID: userID)
        await store.load()
        repository.failNextUpdate = true

        var draft = VehicleDraft(vehicle: original)
        draft.nickname = "Changed locally"
        let saved = await store.save(draft, editing: original)
        XCTAssertFalse(saved)
        XCTAssertEqual(store.vehicles, [original])
        XCTAssertNotNil(store.editorError)
        XCTAssertGreaterThanOrEqual(repository.fetchCalls, 2)
    }

    func testStoreRepairsMissingCurrentSelectionAfterDelete() async throws {
        let current = vehicle(id: UUID(), nickname: "My K5", current: true)
        let remaining = vehicle(id: UUID(), nickname: "Campus SUV", current: false)
        let repository = VehicleRepositoryDouble(now: now, vehicles: [current, remaining])
        repository.autoSelectAfterDelete = false
        let store = VehicleStore(repository: repository, userID: userID)
        await store.load()

        let deleted = await store.delete(current)

        XCTAssertTrue(deleted)
        XCTAssertEqual(store.currentVehicle?.id, remaining.id)
        XCTAssertEqual(store.vehicles.filter(\.isCurrent).count, 1)
        XCTAssertEqual(repository.setCurrentCalls, 1)
    }

    private func kiaDraft() -> VehicleDraft {
        var draft = VehicleDraft()
        draft.nickname = "My K5"
        draft.color = "Midnight grey"
        draft.vehicleType = .sedan
        draft.make = "Kia"
        draft.model = "K5"
        draft.plateSuffix = "404"
        return draft
    }

    private func vehicle(id: UUID, nickname: String, current: Bool) -> Vehicle {
        Vehicle(
            id: id, userID: userID, nickname: nickname, color: "Midnight grey",
            vehicleType: .sedan, make: "Kia", model: "K5", plateSuffix: "404",
            isCurrent: current, createdAt: now, updatedAt: now
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous state")
    }
}

@MainActor
private final class VehicleRepositoryDouble: VehicleRepository {
    var rows: [Vehicle]
    var fetchCalls = 0
    var createCalls = 0
    var deleteCalls = 0
    var setCurrentCalls = 0
    var failNextUpdate = false
    var suspendSetCurrent = false
    var suspendCreate = false
    var suspendDelete = false
    var autoSelectAfterDelete = true
    private let now: Date
    private var continuation: CheckedContinuation<Void, Never>?
    private var createContinuation: CheckedContinuation<Void, Never>?
    private var deleteContinuation: CheckedContinuation<Void, Never>?

    init(now: Date, vehicles: [Vehicle] = []) {
        self.now = now
        rows = vehicles
    }

    func fetchVehicles() async throws -> [Vehicle] {
        fetchCalls += 1
        return rows
    }

    func create(_ vehicle: ValidatedVehicle, userID: UUID) async throws -> Vehicle {
        createCalls += 1
        if suspendCreate { await withCheckedContinuation { createContinuation = $0 } }
        let row = makeVehicle(id: UUID(), userID: userID, value: vehicle, current: false)
        rows.append(row)
        return row
    }

    func update(id: UUID, vehicle: ValidatedVehicle) async throws -> Vehicle {
        if failNextUpdate {
            failNextUpdate = false
            throw VehicleRepositoryError.unavailable
        }
        guard let index = rows.firstIndex(where: { $0.id == id }) else {
            throw VehicleRepositoryError.unavailable
        }
        let updated = makeVehicle(
            id: id, userID: rows[index].userID, value: vehicle, current: rows[index].isCurrent
        )
        rows[index] = updated
        return updated
    }

    func delete(id: UUID) async throws {
        deleteCalls += 1
        if suspendDelete { await withCheckedContinuation { deleteContinuation = $0 } }
        let deletedCurrent = rows.first(where: { $0.id == id })?.isCurrent == true
        rows.removeAll { $0.id == id }
        if autoSelectAfterDelete,
           deletedCurrent,
           let replacement = rows.indices.max(by: { rows[$0].updatedAt < rows[$1].updatedAt }) {
            rows = rows.enumerated().map { index, row in copy(row, current: index == replacement) }
        }
    }

    func setCurrent(id: UUID) async throws -> Vehicle {
        setCurrentCalls += 1
        if suspendSetCurrent {
            await withCheckedContinuation { continuation = $0 }
        }
        guard let selected = rows.first(where: { $0.id == id }) else {
            throw VehicleRepositoryError.unavailable
        }
        rows = rows.map { copy($0, current: $0.id == id) }
        return rows.first(where: { $0.id == selected.id })!
    }

    func resumeSetCurrent() {
        suspendSetCurrent = false
        continuation?.resume()
        continuation = nil
    }

    func resumeCreate() {
        suspendCreate = false
        createContinuation?.resume()
        createContinuation = nil
    }

    func resumeDelete() {
        suspendDelete = false
        deleteContinuation?.resume()
        deleteContinuation = nil
    }

    private func makeVehicle(id: UUID, userID: UUID, value: ValidatedVehicle, current: Bool) -> Vehicle {
        Vehicle(
            id: id, userID: userID, nickname: value.nickname, color: value.color,
            vehicleType: value.vehicleType, make: value.make, model: value.model,
            plateSuffix: value.plateSuffix, isCurrent: current, createdAt: now, updatedAt: now
        )
    }

    private func copy(_ vehicle: Vehicle, current: Bool) -> Vehicle {
        Vehicle(
            id: vehicle.id, userID: vehicle.userID, nickname: vehicle.nickname,
            color: vehicle.color, vehicleType: vehicle.vehicleType, make: vehicle.make,
            model: vehicle.model, plateSuffix: vehicle.plateSuffix, isCurrent: current,
            createdAt: vehicle.createdAt, updatedAt: vehicle.updatedAt
        )
    }
}
