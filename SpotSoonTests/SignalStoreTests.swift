import XCTest
@testable import SpotSoon

@MainActor
final class SignalStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFiltersTerminalAndExpiredSignalsAndSortsEveryVisibleStatus() async {
        let owner = UUID()
        let claimant = UUID()
        let rows = [
            signal(owner: owner, leaving: 500, status: .vacated, claimant: claimant),
            signal(owner: owner, leaving: 300, status: .arrived, claimant: claimant),
            signal(owner: owner, leaving: 200, status: .claimed, claimant: claimant),
            signal(owner: owner, leaving: 100),
            signal(owner: owner, leaving: 0, expiry: 0),
            signal(owner: owner, status: .completed),
            signal(owner: owner, status: .unavailable),
            signal(owner: owner, status: .cancelled),
            signal(owner: owner, status: .expired)
        ]

        let visible = ParkingSignal.visible(rows, at: now)
        XCTAssertEqual(visible.map(\.status), [.active, .claimed, .arrived, .vacated])
    }

    func testLeavingAndExpiryForEveryDurationAndAuthenticatedOwner() async {
        for minutes in [2, 5, 10] {
            let owner = UUID()
            let backend = TestLifecycleBackend(now: now)
            let repository = TestRepository(backend: backend, userID: owner)
            let store = SignalStore(repository: repository, userID: owner)

            let published = await store.publish(
                zone: .campusAStudent, minutes: minutes,
                ownerVehicleID: repository.vehicleID,
                location: insideLocation,
                now: now
            )
            XCTAssertTrue(published)
            let row = try! XCTUnwrap(repository.inserted)
            XCTAssertEqual(row.createdBy, owner)
            XCTAssertEqual(row.leavingAt, now.addingTimeInterval(Double(minutes * 60)))
            XCTAssertEqual(row.expiresAt, row.leavingAt.addingTimeInterval(300))
            XCTAssertEqual(row.status, .active)
        }
    }

    func testPublishingAndClaimingAreBlockedWithoutVehicleSelection() async {
        let owner = UUID()
        let claimant = UUID()
        let row = signal(owner: owner)
        let backend = TestLifecycleBackend(now: now, signals: [row])
        let ownerRepository = TestRepository(backend: backend, userID: owner)
        let ownerStore = SignalStore(repository: ownerRepository, userID: owner)
        let publishedWithoutVehicle = await ownerStore.publish(
            zone: .campusAStudent, minutes: 2, ownerVehicleID: nil,
            location: insideLocation, now: now
        )
        XCTAssertFalse(publishedWithoutVehicle)
        XCTAssertNil(ownerRepository.inserted)
        XCTAssertEqual(ownerStore.publishError, "Select the vehicle you’re leaving in.")

        let claimantRepository = TestRepository(backend: backend, userID: claimant)
        let claimantStore = SignalStore(repository: claimantRepository, userID: claimant)
        await claimantStore.refresh(now: now)
        let claimedWithoutVehicle = await claimantStore.claim(row, claimantVehicleID: nil, now: now)
        XCTAssertFalse(claimedWithoutVehicle)
        XCTAssertEqual(claimantStore.actionErrors[row.id], "Select the vehicle you’re arriving in.")
        XCTAssertNil(claimantRepository.callCounts[.claim])
    }

    func testParkingHintValidationTrimsAndRejectsInvalidValues() throws {
        XCTAssertNil(try ParkingHint.normalize(nil))
        XCTAssertNil(try ParkingHint.normalize("  \n\t "))
        XCTAssertEqual(try ParkingHint.normalize("  Row 3, near the canopy  "), "Row 3, near the canopy")
        XCTAssertEqual(try ParkingHint.normalize(String(repeating: "A", count: 120))?.count, 120)
        XCTAssertThrowsError(try ParkingHint.normalize(String(repeating: "A", count: 121))) {
            XCTAssertEqual($0 as? ParkingHintValidationError, .tooLong)
        }
        XCTAssertThrowsError(try ParkingHint.normalize("Row 3\u{0007}near canopy")) {
            XCTAssertEqual($0 as? ParkingHintValidationError, .invalidCharacters)
        }
    }

    func testPublishRequestEncodesPrivateParkingHintRPCParameter() throws {
        let owner = UUID()
        let request = PublishParkingSignalRequest(
            signal: signal(owner: owner),
            zoneID: ParkingZone.campusAStudent.id,
            ownerVehicleID: UUID(),
            location: insideLocation,
            parkingHint: "Row 3, near shade canopy"
        )
        let data = try JSONEncoder().encode(PublishParameters(request: request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["p_parking_hint"] as? String, "Row 3, near shade canopy")
        XCTAssertNil(object["parking_hint"])
    }

    func testHandoverDetailsDecodesPrivateParkingHint() throws {
        let signalID = UUID()
        let json = """
        {
          "signal_id": "\(signalID.uuidString)",
          "pass_color": null,
          "symbol_name": null,
          "confirmation_number": null,
          "parking_hint": "Row 3, near shade canopy",
          "owner_nickname": "My K5",
          "owner_color": "Midnight grey",
          "owner_vehicle_type": "sedan",
          "owner_make": "Kia",
          "owner_model": "K5",
          "owner_plate_suffix": "404",
          "created_at": 0
        }
        """
        let details = try JSONDecoder().decode(HandoverDetails.self, from: Data(json.utf8))
        XCTAssertEqual(details.signalID, signalID)
        XCTAssertEqual(details.parkingHint, "Row 3, near shade canopy")
    }

    func testPublishNormalizesHintAndParticipantsReceiveItOnlyWhenAuthorized() async throws {
        let owner = UUID()
        let claimant = UUID()
        let stranger = UUID()
        let backend = TestLifecycleBackend(now: now)
        let ownerRepository = TestRepository(backend: backend, userID: owner)
        let ownerStore = SignalStore(repository: ownerRepository, userID: owner)

        let published = await ownerStore.publish(
            zone: .campusAStudent,
            minutes: 2,
            ownerVehicleID: ownerRepository.vehicleID,
            location: insideLocation,
            bayHint: "  Row 3, near shade canopy  ",
            now: now
        )
        XCTAssertTrue(published)
        XCTAssertEqual(ownerRepository.publishedRequest?.parkingHint, "Row 3, near shade canopy")
        let row = try XCTUnwrap(ownerStore.signals.first)
        XCTAssertEqual(ownerStore.handover(for: row)?.parkingHint, "Row 3, near shade canopy")

        let strangerStore = SignalStore(
            repository: TestRepository(backend: backend, userID: stranger), userID: stranger
        )
        await strangerStore.refresh(now: now)
        XCTAssertNil(strangerStore.handover(for: row))
        XCTAssertTrue(strangerStore.handoverDetails.isEmpty)

        let claimantRepository = TestRepository(backend: backend, userID: claimant)
        let claimantStore = SignalStore(repository: claimantRepository, userID: claimant)
        await claimantStore.refresh(now: now)
        XCTAssertNil(claimantStore.handover(for: row))
        let claimedSuccessfully = await claimantStore.claim(
            row, claimantVehicleID: claimantRepository.vehicleID, now: now
        )
        XCTAssertTrue(claimedSuccessfully)
        let claimed = try XCTUnwrap(claimantStore.signals.first)
        XCTAssertEqual(claimantStore.handover(for: claimed)?.parkingHint, "Row 3, near shade canopy")
    }

    func testSnapshotsUseOwnedVehiclesAndRejectForeignVehicleIDs() async throws {
        let owner = UUID()
        let claimant = UUID()
        let backend = TestLifecycleBackend(now: now)
        let ownerRepository = TestRepository(backend: backend, userID: owner)
        let claimantRepository = TestRepository(backend: backend, userID: claimant)
        let ownerStore = SignalStore(repository: ownerRepository, userID: owner)

        do {
            _ = try await ownerRepository.publish(PublishParkingSignalRequest(
                signal: signal(owner: owner),
                zoneID: ParkingZone.campusAStudent.id,
                ownerVehicleID: claimantRepository.vehicleID,
                location: insideLocation
            ))
            XCTFail("Publishing with a foreign vehicle ID should fail")
        } catch {
            XCTAssertEqual(error as? ParkingSignalRepositoryError, .vehicleUnavailable)
        }

        let published = await ownerStore.publish(
            zone: .campusAStudent, minutes: 2,
            ownerVehicleID: ownerRepository.vehicleID,
            location: insideLocation,
            now: now
        )
        XCTAssertTrue(published)
        XCTAssertEqual(ownerRepository.publishedRequest?.zoneID, "campus_a_student")
        XCTAssertEqual(ownerRepository.publishedRequest?.location, insideLocation)
        let signal = try XCTUnwrap(ownerRepository.inserted)
        let publishedSnapshot = try XCTUnwrap(backend.handoverDetails[signal.id]?.ownerVehicle)
        XCTAssertEqual(publishedSnapshot.description, "Midnight grey Kia K5 Sedan · Plate ending 404")

        do {
            _ = try await claimantRepository.claim(
                signalID: signal.id, claimantVehicleID: ownerRepository.vehicleID
            )
            XCTFail("A foreign vehicle ID should be rejected")
        } catch {
            XCTAssertEqual(error as? ParkingSignalRepositoryError, .vehicleUnavailable)
        }

        _ = try await claimantRepository.claim(
            signalID: signal.id, claimantVehicleID: claimantRepository.vehicleID
        )
        let claimedSnapshot = try XCTUnwrap(backend.handoverDetails[signal.id]?.claimantVehicle)
        XCTAssertEqual(claimedSnapshot.description, "Midnight grey Kia K5 Sedan · Plate ending 404")

        backend.vehicles[ownerRepository.vehicleID] = (
            owner,
            VehicleSnapshot(
                nickname: "Edited", color: "Red", vehicleType: .pickup,
                make: nil, model: nil, plateSuffix: nil
            )
        )
        XCTAssertEqual(backend.handoverDetails[signal.id]?.ownerVehicle, publishedSnapshot)
        backend.vehicles[ownerRepository.vehicleID] = nil
        backend.vehicles[claimantRepository.vehicleID] = nil
        XCTAssertEqual(backend.handoverDetails[signal.id]?.ownerVehicle, publishedSnapshot)
        XCTAssertEqual(backend.handoverDetails[signal.id]?.claimantVehicle, claimedSnapshot)
    }

    func testCompleteLifecycleAndPassConsistencyForBothParticipants() async {
        let owner = UUID()
        let claimant = UUID()
        let initial = signal(owner: owner)
        let backend = TestLifecycleBackend(now: now, signals: [initial])
        let ownerStore = SignalStore(repository: TestRepository(backend: backend, userID: owner), userID: owner)
        let claimantRepository = TestRepository(backend: backend, userID: claimant)
        let claimantStore = SignalStore(repository: claimantRepository, userID: claimant)

        await ownerStore.refresh(now: now)
        await claimantStore.refresh(now: now)
        let claimedSuccessfully = await claimantStore.claim(
            initial, claimantVehicleID: claimantRepository.vehicleID, now: now
        )
        XCTAssertTrue(claimedSuccessfully)
        await ownerStore.refresh(now: now)

        let claimed = try! XCTUnwrap(claimantStore.signals.first)
        XCTAssertEqual(claimed.status, .claimed)
        XCTAssertEqual(ownerStore.handover(for: claimed), claimantStore.handover(for: claimed))

        let arrivedSuccessfully = await claimantStore.perform(.arrive, on: claimed, now: now)
        XCTAssertTrue(arrivedSuccessfully)
        await ownerStore.refresh(now: now)
        let arrived = try! XCTUnwrap(ownerStore.signals.first)
        XCTAssertEqual(arrived.status, .arrived)

        let vacatedSuccessfully = await ownerStore.perform(.vacate, on: arrived, now: now)
        XCTAssertTrue(vacatedSuccessfully)
        await claimantStore.refresh(now: now)
        let vacated = try! XCTUnwrap(claimantStore.signals.first)
        XCTAssertEqual(vacated.status, .vacated)

        let completedSuccessfully = await claimantStore.perform(.complete, on: vacated, now: now)
        XCTAssertTrue(completedSuccessfully)
        XCTAssertTrue(claimantStore.signals.isEmpty)
        XCTAssertNil(backend.handoverDetails[initial.id])
        XCTAssertEqual(backend.signals[initial.id]?.status, .completed)
    }

    func testVacatedSignalCanBeMarkedUnavailable() async {
        let owner = UUID()
        let claimant = UUID()
        let vacated = signal(owner: owner, status: .vacated, claimant: claimant)
        let backend = TestLifecycleBackend(now: now, signals: [vacated], details: [handover(signalID: vacated.id)])
        let store = SignalStore(repository: TestRepository(backend: backend, userID: claimant), userID: claimant)
        await store.refresh(now: now)

        let unavailableSucceeded = await store.perform(.unavailable, on: vacated, now: now)
        XCTAssertTrue(unavailableSucceeded)
        XCTAssertTrue(store.signals.isEmpty)
        XCTAssertEqual(backend.signals[vacated.id]?.status, .unavailable)
        XCTAssertNil(backend.handoverDetails[vacated.id])
    }

    func testClaimReleaseFromClaimedAndArrivedInvalidatesOldPass() async {
        for startingStatus in [ParkingSignal.Status.claimed, .arrived] {
            let owner = UUID()
            let claimant = UUID()
            let row = signal(owner: owner, status: startingStatus, claimant: claimant)
            let oldPass = handover(signalID: row.id)
            let backend = TestLifecycleBackend(now: now, signals: [row], details: [oldPass])
            let store = SignalStore(repository: TestRepository(backend: backend, userID: claimant), userID: claimant)
            await store.refresh(now: now)

            XCTAssertEqual(store.handover(for: row), oldPass)
            let released = await store.perform(.release, on: row, now: now)
            XCTAssertTrue(released)
            XCTAssertEqual(store.signals.first?.status, .active)
            XCTAssertNil(store.handover(for: store.signals[0]))
            let releasedDetails = try! XCTUnwrap(backend.handoverDetails[row.id])
            XCTAssertEqual(releasedDetails.ownerVehicle, oldPass.ownerVehicle)
            XCTAssertEqual(releasedDetails.parkingHint, oldPass.parkingHint)
            XCTAssertNil(releasedDetails.claimantVehicle)
            XCTAssertNil(releasedDetails.pass)

            let ownerStore = SignalStore(
                repository: TestRepository(backend: backend, userID: owner), userID: owner
            )
            await ownerStore.refresh(now: now)
            XCTAssertEqual(ownerStore.handover(for: ownerStore.signals[0])?.parkingHint, oldPass.parkingHint)
            await store.refresh(now: now)
            XCTAssertTrue(store.handoverDetails.isEmpty)

            let repository = TestRepository(backend: backend, userID: claimant)
            let reclaimed = try! await repository.claim(
                signalID: row.id, claimantVehicleID: repository.vehicleID
            )
            XCTAssertEqual(reclaimed.status, .claimed)
            XCTAssertNotEqual(backend.handoverDetails[row.id]?.pass, oldPass.pass)
            XCTAssertNotNil(backend.handoverDetails[row.id]?.claimantVehicle)
        }
    }

    func testCreatorCanCancelActiveClaimedAndArrivedSignals() async {
        for startingStatus in [ParkingSignal.Status.active, .claimed, .arrived] {
            let owner = UUID()
            let claimant = startingStatus == .active ? nil : UUID()
            let row = signal(owner: owner, status: startingStatus, claimant: claimant)
            let details = claimant == nil ? [] : [handover(signalID: row.id)]
            let backend = TestLifecycleBackend(now: now, signals: [row], details: details)
            let store = SignalStore(repository: TestRepository(backend: backend, userID: owner), userID: owner)
            await store.refresh(now: now)

            let cancelled = await store.perform(.cancel, on: row, now: now)
            XCTAssertTrue(cancelled)
            XCTAssertTrue(store.signals.isEmpty)
            XCTAssertEqual(backend.signals[row.id]?.status, .cancelled)
            XCTAssertNil(backend.handoverDetails[row.id])
        }
    }

    func testTerminalTransitionsDeletePrivateParkingHintsWithHandoverDetails() async {
        let owner = UUID()
        let claimant = UUID()
        let scenarios: [(ParkingSignal.Status, ParkingSignal.LifecycleAction, UUID)] = [
            (.claimed, .cancel, owner),
            (.vacated, .complete, claimant),
            (.vacated, .unavailable, claimant)
        ]

        for (status, action, actor) in scenarios {
            let row = signal(owner: owner, status: status, claimant: claimant)
            let details = handover(signalID: row.id)
            let backend = TestLifecycleBackend(now: now, signals: [row], details: [details])
            let store = SignalStore(
                repository: TestRepository(backend: backend, userID: actor), userID: actor
            )
            await store.refresh(now: now)
            XCTAssertEqual(store.handover(for: row)?.parkingHint, details.parkingHint)

            let succeeded = await store.perform(action, on: row, now: now)
            XCTAssertTrue(succeeded)
            XCTAssertNil(backend.handoverDetails[row.id])
            XCTAssertNil(store.handoverDetails[row.id])
        }
    }

    func testUnauthorizedTransitionsAreRejectedBeforeRepositoryCalls() async {
        let owner = UUID()
        let claimant = UUID()
        let stranger = UUID()
        let claimed = signal(owner: owner, status: .claimed, claimant: claimant)
        let backend = TestLifecycleBackend(now: now, signals: [claimed], details: [handover(signalID: claimed.id)])
        let repository = TestRepository(backend: backend, userID: stranger)
        let store = SignalStore(repository: repository, userID: stranger)
        await store.refresh(now: now)

        for action in [ParkingSignal.LifecycleAction.cancel, .release, .arrive, .vacate, .complete, .unavailable] {
            let succeeded = await store.perform(action, on: claimed, now: now)
            XCTAssertFalse(succeeded)
        }
        XCTAssertTrue(repository.callCounts.isEmpty)

        let ownerRepository = TestRepository(backend: backend, userID: owner)
        let ownerStore = SignalStore(repository: ownerRepository, userID: owner)
        let ownerArrived = await ownerStore.perform(.arrive, on: claimed, now: now)
        XCTAssertFalse(ownerArrived)
        XCTAssertTrue(ownerRepository.callCounts.isEmpty)
    }

    func testCreatorClaimantAndUnrelatedUserStatesAndActions() {
        let owner = UUID()
        let claimant = UUID()
        let stranger = UUID()

        let active = signal(owner: owner)
        XCTAssertEqual(active.userState(for: owner), .yourSignal)
        XCTAssertEqual(active.userState(for: claimant), .available)
        XCTAssertEqual(active.allowedActions(for: owner), [.cancel])
        XCTAssertEqual(active.allowedActions(for: claimant), [.claim])

        let claimed = signal(owner: owner, status: .claimed, claimant: claimant)
        XCTAssertEqual(claimed.userState(for: owner), .someoneHeadingThere)
        XCTAssertEqual(claimed.userState(for: claimant), .youreHeadingThere)
        XCTAssertEqual(claimed.userState(for: stranger), .claimed)

        let arrived = signal(owner: owner, status: .arrived, claimant: claimant)
        XCTAssertEqual(arrived.userState(for: owner), .claimantArrived)
        XCTAssertEqual(arrived.userState(for: claimant), .youAreHere)
        XCTAssertEqual(arrived.userState(for: stranger), .handoverInProgress)

        let vacated = signal(owner: owner, status: .vacated, claimant: claimant)
        XCTAssertEqual(vacated.userState(for: claimant), .driverLeft)
        XCTAssertEqual(vacated.userState(for: owner), .waitingForClaimant)
        XCTAssertEqual(vacated.userState(for: stranger), .handoverInProgress)
    }

    func testSuccessfulClaimPresentsLiveHandoverAfterClaimSheetDismisses() {
        let signalID = UUID()
        var navigation = HandoverNavigationState()

        navigation.claimSucceeded(signalID: signalID)
        XCTAssertNil(navigation.liveRoute, "The claim sheet must dismiss before presenting another cover")
        XCTAssertEqual(navigation.pendingClaimRoute?.signalID, signalID)

        navigation.claimSheetDismissed()
        XCTAssertNil(navigation.pendingClaimRoute)
        XCTAssertEqual(navigation.liveRoute?.signalID, signalID)
    }

    func testCompactRowsExposeOnlyClaimOrResumeActionsByRole() {
        let owner = UUID()
        let claimant = UUID()
        let stranger = UUID()
        let active = signal(owner: owner)
        let claimed = signal(owner: owner, status: .claimed, claimant: claimant)

        XCTAssertEqual(active.compactAction(for: owner), .none)
        XCTAssertEqual(active.compactAction(for: claimant), .claim)
        XCTAssertEqual(claimed.compactAction(for: owner), .none)
        XCTAssertEqual(claimed.compactAction(for: claimant), .resumeHandover)
        XCTAssertEqual(claimed.compactAction(for: stranger), .none)
        XCTAssertEqual(claimed.userState(for: owner).message, "Someone is heading there")
        XCTAssertEqual(claimed.userState(for: claimant).message, "You’re heading there")
        XCTAssertEqual(claimed.userState(for: stranger).message, "Claimed")
    }

    func testResumeAndFullPassCloseReturnToLiveHandover() {
        let signalID = UUID()
        var navigation = HandoverNavigationState()
        var pass = HandoverPassPresentationState()

        navigation.resume(signalID: signalID)
        pass.show()
        XCTAssertTrue(pass.isPresented)
        XCTAssertEqual(navigation.liveRoute?.signalID, signalID)

        pass.close()
        XCTAssertFalse(pass.isPresented)
        XCTAssertEqual(navigation.liveRoute?.signalID, signalID)

        navigation.closeLiveHandover()
        XCTAssertNil(navigation.liveRoute)
    }

    func testRelaunchRestoresOnlyCurrentClaimantsNonterminalHandover() {
        let owner = UUID()
        let claimant = UUID()
        let stranger = UUID()

        for status in [ParkingSignal.Status.claimed, .arrived, .vacated] {
            let row = signal(owner: owner, status: status, claimant: claimant)
            XCTAssertEqual(
                HandoverNavigationState.restorableClaimantSignal(
                    in: [row], userID: claimant, now: now
                )?.id,
                row.id
            )
            XCTAssertNil(HandoverNavigationState.restorableClaimantSignal(
                in: [row], userID: owner, now: now
            ))
            XCTAssertNil(HandoverNavigationState.restorableClaimantSignal(
                in: [row], userID: stranger, now: now
            ))
        }

        let expired = signal(
            owner: owner, leaving: -600, expiry: -1, status: .claimed, claimant: claimant
        )
        let terminal = signal(owner: owner, status: .completed, claimant: claimant)
        XCTAssertNil(HandoverNavigationState.restorableClaimantSignal(
            in: [expired, terminal], userID: claimant, now: now
        ))
    }

    func testUnrelatedUserNeverKeepsLeakedPrivateDetails() async {
        let owner = UUID()
        let claimant = UUID()
        let row = signal(owner: owner, status: .arrived, claimant: claimant)
        let backend = TestLifecycleBackend(now: now, signals: [row], details: [handover(signalID: row.id)])
        let repository = TestRepository(backend: backend, userID: UUID())
        repository.simulateLeakyPrivateQuery = true
        let store = SignalStore(repository: repository, userID: repository.userID)

        await store.refresh(now: now)
        XCTAssertNotNil(store.signals.first)
        XCTAssertNil(store.handover(for: row))
        XCTAssertTrue(store.handoverDetails.isEmpty)
    }

    func testVehicleInputValidationAndNormalization() throws {
        var missing = VehicleDraft()
        XCTAssertThrowsError(try missing.validated())
        missing.nickname = "Campus car"
        missing.color = "Blue"
        missing.plateSuffix = "1234"
        XCTAssertThrowsError(try missing.validated())
        missing.plateSuffix = "A-1"
        XCTAssertThrowsError(try missing.validated())

        var draft = VehicleDraft()
        draft.nickname = "  My SUV "
        draft.color = "  Dark blue "
        draft.vehicleType = .suv
        draft.plateSuffix = " a7b "
        let value = try draft.validated()
        XCTAssertEqual(value.color, "Dark blue")
        XCTAssertEqual(value.vehicleType, .suv)
        XCTAssertEqual(value.plateSuffix, "A7B")
    }

    func testRapidDuplicateClaimAndLifecycleActionsAreBlockedPerSignal() async {
        let owner = UUID()
        let claimant = UUID()
        let active = signal(owner: owner)
        let backend = TestLifecycleBackend(now: now, signals: [active])
        let repository = TestRepository(backend: backend, userID: claimant)
        repository.suspendedAction = .claim
        let store = SignalStore(repository: repository, userID: claimant)
        await store.refresh(now: now)

        let first = Task { await store.claim(active, claimantVehicleID: repository.vehicleID, now: now) }
        await waitUntil { repository.callCounts[.claim] == 1 }
        XCTAssertTrue(store.isPerformingAction(on: active.id))
        let duplicateClaimed = await store.claim(active, claimantVehicleID: repository.vehicleID, now: now)
        XCTAssertFalse(duplicateClaimed)
        XCTAssertEqual(repository.callCounts[.claim], 1)
        repository.resumeSuspendedAction()
        let firstClaimed = await first.value
        XCTAssertTrue(firstClaimed)

        let claimed = try! XCTUnwrap(store.signals.first)
        repository.suspendedAction = .arrive
        let arrival = Task { await store.perform(.arrive, on: claimed, now: now) }
        await waitUntil { repository.callCounts[.arrive] == 1 }
        let duplicateArrived = await store.perform(.arrive, on: claimed, now: now)
        XCTAssertFalse(duplicateArrived)
        XCTAssertEqual(repository.callCounts[.arrive], 1)
        repository.resumeSuspendedAction()
        let arrivalSucceeded = await arrival.value
        XCTAssertTrue(arrivalSucceeded)
    }

    func testCancellationAndClaimRacesHaveOneConsistentOutcome() async throws {
        let owner = UUID()
        let claimant = UUID()

        let first = signal(owner: owner)
        let firstBackend = TestLifecycleBackend(now: now, signals: [first])
        let claimantRepository = TestRepository(backend: firstBackend, userID: claimant)
        let ownerRepository = TestRepository(backend: firstBackend, userID: owner)
        _ = try await claimantRepository.claim(signalID: first.id, claimantVehicleID: claimantRepository.vehicleID)
        _ = try await ownerRepository.cancel(signalID: first.id)
        XCTAssertEqual(firstBackend.signals[first.id]?.status, .cancelled)
        XCTAssertNil(firstBackend.handoverDetails[first.id])

        let second = signal(owner: owner)
        let secondBackend = TestLifecycleBackend(now: now, signals: [second])
        let secondOwner = TestRepository(backend: secondBackend, userID: owner)
        let secondClaimant = TestRepository(backend: secondBackend, userID: claimant)
        _ = try await secondOwner.cancel(signalID: second.id)
        do {
            _ = try await secondClaimant.claim(signalID: second.id, claimantVehicleID: secondClaimant.vehicleID)
            XCTFail("Claim should lose after cancellation")
        } catch {
            XCTAssertEqual(error as? ParkingSignalRepositoryError, .signalUnavailable)
        }
        XCTAssertEqual(secondBackend.signals[second.id]?.status, .cancelled)
    }

    func testRealtimeRefreshReplacesThenRemovesSignal() async {
        let owner = UUID()
        let claimant = UUID()
        let active = signal(owner: owner)
        let backend = TestLifecycleBackend(now: now, signals: [active])
        let repository = TestRepository(backend: backend, userID: owner)
        let store = SignalStore(repository: repository, userID: owner)
        let run = Task { await store.run() }
        await waitUntil { repository.isObserving }

        backend.signals[active.id] = signal(
            id: active.id, owner: owner, status: .arrived, claimant: claimant
        )
        backend.handoverDetails[active.id] = handover(signalID: active.id)
        await repository.emit(.changed)
        await waitUntil { store.signals.first?.status == .arrived }
        XCTAssertNotNil(store.handoverDetails[active.id])

        backend.signals[active.id] = signal(id: active.id, owner: owner, status: .completed)
        backend.handoverDetails[active.id] = nil
        await repository.emit(.changed)
        await waitUntil { store.signals.isEmpty }
        XCTAssertTrue(store.handoverDetails.isEmpty)

        repository.finishObservation()
        run.cancel()
        await run.value
    }

    func testRealtimeUpdatesPreserveOtherZoneAndSelectedZoneFiltering() async {
        let owner = UUID()
        let claimant = UUID()
        let campusA = signal(owner: owner, zone: .campusAStudent)
        let campusB = signal(owner: owner, zone: .campusBStudent)
        let backend = TestLifecycleBackend(now: now, signals: [campusA, campusB])
        let repository = TestRepository(backend: backend, userID: owner)
        let store = SignalStore(repository: repository, userID: owner)
        let run = Task { await store.run() }
        await waitUntil { repository.isObserving && store.signals.count == 2 }

        backend.signals[campusB.id] = signal(
            id: campusB.id, owner: owner, status: .arrived,
            claimant: claimant, zone: .campusBStudent
        )
        await repository.emit(.changed)
        await waitUntil { store.signals.first(where: { $0.id == campusB.id })?.status == .arrived }

        XCTAssertNotNil(store.signals.first(where: { $0.id == campusA.id }))
        XCTAssertEqual(ParkingSignal.visible(store.signals, in: .campusAStudent, at: now).map(\.id), [campusA.id])
        XCTAssertEqual(ParkingSignal.visible(store.signals, in: .campusBStudent, at: now).map(\.id), [campusB.id])

        backend.signals[campusB.id] = signal(
            id: campusB.id, owner: owner, status: .completed, zone: .campusBStudent
        )
        await repository.emit(.changed)
        await waitUntil { store.signals.count == 1 }
        XCTAssertEqual(store.signals.first?.id, campusA.id)

        repository.finishObservation()
        run.cancel()
        await run.value
    }

    private func signal(
        id: UUID = UUID(),
        owner: UUID,
        leaving: TimeInterval = 120,
        expiry: TimeInterval = 900,
        status: ParkingSignal.Status = .active,
        claimant: UUID? = nil,
        zone: ParkingZone = .campusAStudent
    ) -> ParkingSignal {
        let keepsClaim = [.claimed, .arrived, .vacated].contains(status)
        return ParkingSignal(
            id: id, createdBy: owner, zoneID: zone.id,
            campus: zone.campus, zone: zone.name,
            leavingAt: now.addingTimeInterval(leaving),
            expiresAt: now.addingTimeInterval(expiry), status: status, createdAt: now,
            claimedBy: keepsClaim ? claimant : nil,
            claimedAt: keepsClaim ? now : nil
        )
    }

    private var insideLocation: LocationReading {
        LocationReading(
            latitude: 26.164736,
            longitude: 50.543676,
            horizontalAccuracy: 8,
            timestamp: now
        )
    }

    private func handover(signalID: UUID) -> HandoverDetails {
        HandoverDetails(
            signalID: signalID, passColor: .purple, symbolName: "hare.fill",
            confirmationNumber: "42",
            ownerVehicle: VehicleSnapshot(
                nickname: "My K5", color: "Midnight grey", vehicleType: .sedan,
                make: "Kia", model: "K5", plateSuffix: "404"
            ),
            claimantVehicle: VehicleSnapshot(
                nickname: "Campus SUV", color: "Silver", vehicleType: .suv,
                make: nil, model: nil, plateSuffix: "7AB"
            ),
            parkingHint: "Row 3, near shade canopy",
            createdAt: now
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
private final class TestLifecycleBackend {
    let now: Date
    var signals: [UUID: ParkingSignal]
    var handoverDetails: [UUID: HandoverDetails]
    var vehicles: [UUID: (owner: UUID, snapshot: VehicleSnapshot)] = [:]
    private var passSequence = 0

    init(now: Date, signals: [ParkingSignal] = [], details: [HandoverDetails] = []) {
        self.now = now
        self.signals = Dictionary(uniqueKeysWithValues: signals.map { ($0.id, $0) })
        self.handoverDetails = Dictionary(uniqueKeysWithValues: details.map { ($0.signalID, $0) })
    }

    func registerVehicle(id: UUID, userID: UUID, snapshot: VehicleSnapshot) {
        vehicles[id] = (userID, snapshot)
    }

    func publish(
        _ signal: ParkingSignal,
        userID: UUID,
        vehicleID: UUID,
        parkingHint: String?
    ) throws -> ParkingSignal {
        guard signal.createdBy == userID,
              let vehicle = vehicles[vehicleID], vehicle.owner == userID else {
            throw ParkingSignalRepositoryError.vehicleUnavailable
        }
        signals[signal.id] = signal
        handoverDetails[signal.id] = HandoverDetails(
            signalID: signal.id, passColor: nil, symbolName: nil, confirmationNumber: nil,
            ownerVehicle: vehicle.snapshot, claimantVehicle: nil,
            parkingHint: parkingHint, createdAt: now
        )
        return signal
    }

    func claim(_ id: UUID, userID: UUID, vehicleID: UUID) throws -> ParkingSignal {
        guard let row = signals[id], row.status == .active, row.createdBy != userID, row.expiresAt > now else {
            throw ParkingSignalRepositoryError.signalUnavailable
        }
        guard let vehicle = vehicles[vehicleID], vehicle.owner == userID else {
            throw ParkingSignalRepositoryError.vehicleUnavailable
        }
        let updated = copy(row, status: .claimed, claimant: userID)
        signals[id] = updated
        passSequence += 1
        let ownerVehicle = handoverDetails[id]?.ownerVehicle ?? Self.ownerSnapshot
        let parkingHint = handoverDetails[id]?.parkingHint
        handoverDetails[id] = HandoverDetails(
            signalID: id, passColor: .blue, symbolName: "bird.fill",
            confirmationNumber: String(format: "%02d", passSequence),
            ownerVehicle: ownerVehicle, claimantVehicle: vehicle.snapshot,
            parkingHint: parkingHint, createdAt: now
        )
        return updated
    }

    func transition(_ action: ParkingSignal.LifecycleAction, id: UUID, userID: UUID) throws -> ParkingSignal {
        guard let row = signals[id], row.expiresAt > now else {
            throw ParkingSignalRepositoryError.transitionUnavailable
        }
        let updated: ParkingSignal
        switch action {
        case .arrive where row.status == .claimed && row.claimedBy == userID:
            updated = copy(row, status: .arrived, claimant: row.claimedBy)
        case .release where [.claimed, .arrived].contains(row.status) && row.claimedBy == userID:
            updated = copy(row, status: .active, claimant: nil)
            if let details = handoverDetails[id] {
                handoverDetails[id] = HandoverDetails(
                    signalID: id, passColor: nil, symbolName: nil, confirmationNumber: nil,
                    ownerVehicle: details.ownerVehicle, claimantVehicle: nil,
                    parkingHint: details.parkingHint, createdAt: details.createdAt
                )
            }
        case .cancel where [.active, .claimed, .arrived].contains(row.status) && row.createdBy == userID:
            updated = copy(row, status: .cancelled, claimant: nil)
            handoverDetails[id] = nil
        case .vacate where row.status == .arrived && row.createdBy == userID:
            updated = copy(row, status: .vacated, claimant: row.claimedBy)
        case .complete where row.status == .vacated && row.claimedBy == userID:
            updated = copy(row, status: .completed, claimant: nil)
            handoverDetails[id] = nil
        case .unavailable where row.status == .vacated && row.claimedBy == userID:
            updated = copy(row, status: .unavailable, claimant: nil)
            handoverDetails[id] = nil
        default:
            throw ParkingSignalRepositoryError.transitionUnavailable
        }
        signals[id] = updated
        return updated
    }

    private func copy(_ row: ParkingSignal, status: ParkingSignal.Status, claimant: UUID?) -> ParkingSignal {
        ParkingSignal(
            id: row.id, createdBy: row.createdBy, zoneID: row.zoneID,
            campus: row.campus, zone: row.zone,
            leavingAt: row.leavingAt, expiresAt: row.expiresAt, status: status,
            createdAt: row.createdAt, claimedBy: claimant,
            claimedAt: claimant == nil ? nil : (row.claimedAt ?? now)
        )
    }

    private static let ownerSnapshot = VehicleSnapshot(
        nickname: "My K5", color: "Midnight grey", vehicleType: .sedan,
        make: "Kia", model: "K5", plateSuffix: "404"
    )
}

@MainActor
private final class TestRepository: ParkingSignalRepository {
    let backend: TestLifecycleBackend
    let userID: UUID
    let vehicleID: UUID
    var inserted: ParkingSignal?
    var publishedRequest: PublishParkingSignalRequest?
    var callCounts: [ParkingSignal.LifecycleAction: Int] = [:]
    var suspendedAction: ParkingSignal.LifecycleAction?
    var simulateLeakyPrivateQuery = false
    private var suspension: CheckedContinuation<Void, Never>?
    private var eventContinuation: AsyncStream<SignalEvent>.Continuation?
    var isObserving: Bool { eventContinuation != nil }

    init(backend: TestLifecycleBackend, userID: UUID) {
        self.backend = backend
        self.userID = userID
        vehicleID = UUID()
        backend.registerVehicle(
            id: vehicleID,
            userID: userID,
            snapshot: VehicleSnapshot(
                nickname: "My K5", color: "Midnight grey", vehicleType: .sedan,
                make: "Kia", model: "K5", plateSuffix: "404"
            )
        )
    }

    func fetchFeed(now: Date) async throws -> SignalFeed {
        let rows = Array(backend.signals.values)
        let details: [UUID: HandoverDetails]
        if simulateLeakyPrivateQuery {
            details = backend.handoverDetails
        } else {
            let permitted = Set(rows.filter { $0.createdBy == userID || $0.claimedBy == userID }.map(\.id))
            details = backend.handoverDetails.filter { permitted.contains($0.key) }
        }
        return SignalFeed(signals: rows, handoverDetails: details)
    }

    func publish(_ request: PublishParkingSignalRequest) async throws -> ParkingSignal {
        publishedRequest = request
        inserted = request.signal
        return try backend.publish(
            request.signal,
            userID: userID,
            vehicleID: request.ownerVehicleID,
            parkingHint: request.parkingHint
        )
    }

    func claim(signalID: UUID, claimantVehicleID: UUID) async throws -> ParkingSignal {
        await before(.claim)
        return try backend.claim(signalID, userID: userID, vehicleID: claimantVehicleID)
    }

    func markArrived(signalID: UUID) async throws -> ParkingSignal { try await transition(.arrive, signalID) }
    func releaseClaim(signalID: UUID) async throws -> ParkingSignal { try await transition(.release, signalID) }
    func cancel(signalID: UUID) async throws -> ParkingSignal { try await transition(.cancel, signalID) }
    func markVacated(signalID: UUID) async throws -> ParkingSignal { try await transition(.vacate, signalID) }
    func complete(signalID: UUID) async throws -> ParkingSignal { try await transition(.complete, signalID) }
    func markUnavailable(signalID: UUID) async throws -> ParkingSignal { try await transition(.unavailable, signalID) }

    private func transition(_ action: ParkingSignal.LifecycleAction, _ signalID: UUID) async throws -> ParkingSignal {
        await before(action)
        return try backend.transition(action, id: signalID, userID: userID)
    }

    private func before(_ action: ParkingSignal.LifecycleAction) async {
        callCounts[action, default: 0] += 1
        if suspendedAction == action {
            await withCheckedContinuation { suspension = $0 }
        }
    }

    func resumeSuspendedAction() {
        suspendedAction = nil
        suspension?.resume()
        suspension = nil
    }

    func observe(_ receive: @escaping @MainActor (SignalEvent) async -> Void) async throws {
        let stream = AsyncStream<SignalEvent> { eventContinuation = $0 }
        for await event in stream { await receive(event) }
    }

    func emit(_ event: SignalEvent) async {
        eventContinuation?.yield(event)
        await Task.yield()
    }

    func finishObservation() {
        eventContinuation?.finish()
        eventContinuation = nil
    }
}
