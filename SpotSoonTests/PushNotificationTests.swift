import UserNotifications
import XCTest
@testable import SpotSoon

final class PushNotificationTests: XCTestCase {
    func testPermissionStateMapping() {
        XCTAssertEqual(NotificationPermissionState(.notDetermined), .notRequested)
        XCTAssertEqual(NotificationPermissionState(.denied), .denied)
        XCTAssertEqual(NotificationPermissionState(.authorized), .authorized)
        XCTAssertEqual(NotificationPermissionState(.provisional), .provisional)
        XCTAssertTrue(NotificationPermissionState(.authorized).canRegister)
        XCTAssertFalse(NotificationPermissionState(.denied).canRegister)
    }

    func testAPNsTokenUsesLowercaseHexEncoding() {
        XCTAssertEqual(Data([0x00, 0x0f, 0xa5, 0xff]).hexadecimalString, "000fa5ff")
    }

    func testRepositoryErrorIsSafeAndUserFacing() {
        XCTAssertEqual(
            PushNotificationRepositoryError.registrationRejected.localizedDescription,
            "SpotSoon could not register this device for notifications."
        )
    }

    func testPayloadDecodesOnlyMinimalValidFields() throws {
        let eventID = UUID(), signalID = UUID()
        let payload = try XCTUnwrap(SpotSoonNotificationPayload(userInfo: [
            "notification_event_id": eventID.uuidString,
            "signal_id": signalID.uuidString,
            "lifecycle_event": "claimant_arrived",
            "aps": ["alert": "generic"]
        ]))
        XCTAssertEqual(payload, .init(eventID: eventID, signalID: signalID, lifecycleEvent: .claimantArrived))
        XCTAssertNil(SpotSoonNotificationPayload(userInfo: ["signal_id": signalID.uuidString]))
    }

    func testRoutingRequiresCurrentParticipantAndActiveSignal() {
        let owner = UUID(), claimant = UUID(), outsider = UUID(), signalID = UUID()
        let payload = SpotSoonNotificationPayload(
            eventID: UUID(), signalID: signalID, lifecycleEvent: .signalVacated
        )
        let signal = makeSignal(id: signalID, owner: owner, claimant: claimant, status: .vacated)
        XCTAssertEqual(
            NotificationRouter.decision(for: payload, signals: [signal], userID: claimant, now: .now),
            .liveHandover(signalID: signalID)
        )
        XCTAssertEqual(
            NotificationRouter.decision(for: payload, signals: [signal], userID: outsider, now: .now),
            .map(message: "This parking handover is no longer available.")
        )
        XCTAssertEqual(
            NotificationRouter.decision(for: payload, signals: [], userID: owner, now: .now),
            .map(message: "This parking handover is no longer available.")
        )
        let released = makeSignal(id: signalID, owner: owner, claimant: nil, status: .active)
        XCTAssertEqual(
            NotificationRouter.decision(for: payload, signals: [released], userID: owner, now: .now),
            .map(message: "This parking handover has changed. Open SpotSoon to see the latest status.")
        )
    }

    @MainActor
    func testTokenSynchronizationAndDuplicateSuppression() async {
        let repository = NotificationRepositorySpy()
        let service = NotificationService(centerClient: DeniedNotificationCenter(), deviceID: UUID())
        await service.configure(repository: repository)
        let token = Data(repeating: 0xab, count: 32)
        service.receivedDeviceToken(token)
        await service.retryTokenSynchronization()
        await service.retryTokenSynchronization()
        XCTAssertEqual(repository.registeredTokens, [token.hexadecimalString])
        XCTAssertEqual(repository.environments, [.current])
    }

    private func makeSignal(
        id: UUID, owner: UUID, claimant: UUID?, status: ParkingSignal.Status
    ) -> ParkingSignal {
        ParkingSignal(
            id: id, createdBy: owner, campus: .campusA, zone: "Main Car Park",
            leavingAt: .now.addingTimeInterval(60), expiresAt: .now.addingTimeInterval(600),
            status: status, createdAt: .now, claimedBy: claimant, claimedAt: .now
        )
    }
}

private struct DeniedNotificationCenter: NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization() async throws -> Bool { false }
}

@MainActor
private final class NotificationRepositorySpy: PushNotificationRepository {
    var registeredTokens: [String] = []
    var environments: [PushEnvironment] = []
    func register(token: String, deviceID: UUID, environment: PushEnvironment) async throws {
        registeredTokens.append(token)
        environments.append(environment)
    }
    func deactivate(deviceID: UUID, environment: PushEnvironment) async throws {}
}
