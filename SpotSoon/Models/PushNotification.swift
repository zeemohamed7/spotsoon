import Foundation
import UserNotifications

nonisolated enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production

    static var current: Self {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

nonisolated enum NotificationPermissionState: String, Equatable, Sendable {
    case notRequested, denied, authorized, provisional, ephemeral, restricted

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notRequested
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        @unknown default: self = .restricted
        }
    }

    var canRegister: Bool { [.authorized, .provisional, .ephemeral].contains(self) }
    var title: String {
        switch self {
        case .notRequested: "Not enabled"
        case .denied: "Off"
        case .authorized: "On"
        case .provisional: "Quietly enabled"
        case .ephemeral: "Temporarily enabled"
        case .restricted: "Restricted"
        }
    }
}

nonisolated enum ParkingNotificationEvent: String, Codable, Sendable {
    case signalClaimed = "signal_claimed"
    case claimantArrived = "claimant_arrived"
    case signalVacated = "signal_vacated"
    case claimReleased = "claim_released"
    case signalUnavailable = "signal_unavailable"
    case activeClaimExpired = "active_claim_expired"
}

nonisolated struct SpotSoonNotificationPayload: Codable, Equatable, Sendable {
    let eventID: UUID
    let signalID: UUID
    let lifecycleEvent: ParkingNotificationEvent

    enum CodingKeys: String, CodingKey {
        case eventID = "notification_event_id"
        case signalID = "signal_id"
        case lifecycleEvent = "lifecycle_event"
    }

    init(eventID: UUID, signalID: UUID, lifecycleEvent: ParkingNotificationEvent) {
        self.eventID = eventID
        self.signalID = signalID
        self.lifecycleEvent = lifecycleEvent
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let event = userInfo[CodingKeys.eventID.rawValue] as? String,
              let signal = userInfo[CodingKeys.signalID.rawValue] as? String,
              let lifecycle = userInfo[CodingKeys.lifecycleEvent.rawValue] as? String,
              let eventID = UUID(uuidString: event),
              let signalID = UUID(uuidString: signal),
              let lifecycleEvent = ParkingNotificationEvent(rawValue: lifecycle) else { return nil }
        self.init(eventID: eventID, signalID: signalID, lifecycleEvent: lifecycleEvent)
    }
}

nonisolated enum NotificationRoutingDecision: Equatable, Sendable {
    case liveHandover(signalID: UUID)
    case map(message: String)
}

nonisolated enum NotificationRouter {
    static func decision(
        for payload: SpotSoonNotificationPayload,
        signals: [ParkingSignal],
        userID: UUID,
        now: Date = .now
    ) -> NotificationRoutingDecision {
        guard let signal = signals.first(where: { $0.id == payload.signalID }),
              signal.expiresAt > now,
              !signal.status.isTerminal,
              signal.createdBy == userID || signal.claimedBy == userID else {
            return .map(message: "This parking handover is no longer available.")
        }
        guard [.claimed, .arrived, .vacated].contains(signal.status) else {
            return .map(message: "This parking handover has changed. Open SpotSoon to see the latest status.")
        }
        return .liveHandover(signalID: signal.id)
    }
}

nonisolated extension Data {
    var hexadecimalString: String { map { String(format: "%02x", $0) }.joined() }
}
