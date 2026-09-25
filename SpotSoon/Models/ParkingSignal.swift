import Foundation

nonisolated struct ParkingSignal: Codable, Identifiable, Equatable, Sendable {
    enum Campus: String, Codable, CaseIterable, Sendable {
        case campusA = "campus_a", campusB = "campus_b"
        var title: String { self == .campusA ? "Campus A" : "Campus B" }
        var zones: [String] { self == .campusA ? ["A1", "A2", "A3"] : ["B1", "B2", "B3"] }
    }
    enum Status: String, Codable, Sendable {
        case active, claimed, arrived, vacated
        case completed, unavailable, cancelled, expired

        var isTerminal: Bool {
            switch self {
            case .completed, .unavailable, .cancelled, .expired: true
            case .active, .claimed, .arrived, .vacated: false
            }
        }
    }

    enum UserState: Equatable, Sendable {
        case yourSignal
        case available
        case someoneHeadingThere
        case youreHeadingThere
        case claimed
        case claimantArrived
        case youAreHere
        case handoverInProgress
        case driverLeft
        case waitingForClaimant

        var message: String {
            switch self {
            case .yourSignal: "Your signal"
            case .available: "Available"
            case .someoneHeadingThere: "Someone is heading there"
            case .youreHeadingThere: "You’re heading there"
            case .claimed: "Claimed"
            case .claimantArrived: "The claimant has arrived"
            case .youAreHere: "You told the driver you’re here"
            case .handoverInProgress: "Handover in progress"
            case .driverLeft: "The driver has left"
            case .waitingForClaimant: "Waiting for the claimant to confirm"
            }
        }
    }

    enum LifecycleAction: Hashable, Sendable {
        case claim, cancel, release, arrive, vacate, complete, unavailable, showPass
    }

    let id: UUID
    let createdBy: UUID
    let campus: Campus
    let zone: String
    let leavingAt: Date
    let expiresAt: Date
    let status: Status
    let createdAt: Date
    let claimedBy: UUID?
    let claimedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, campus, zone, status
        case createdBy = "created_by", leavingAt = "leaving_at"
        case expiresAt = "expires_at", createdAt = "created_at"
        case claimedBy = "claimed_by", claimedAt = "claimed_at"
    }

    init(
        id: UUID,
        createdBy: UUID,
        campus: Campus,
        zone: String,
        leavingAt: Date,
        expiresAt: Date,
        status: Status,
        createdAt: Date,
        claimedBy: UUID? = nil,
        claimedAt: Date? = nil
    ) {
        self.id = id
        self.createdBy = createdBy
        self.campus = campus
        self.zone = zone
        self.leavingAt = leavingAt
        self.expiresAt = expiresAt
        self.status = status
        self.createdAt = createdAt
        self.claimedBy = claimedBy
        self.claimedAt = claimedAt
    }

    static func leaving(userID: UUID, campus: Campus, zone: String, minutes: Int, now: Date) -> Self {
        let leavingAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        return Self(id: UUID(), createdBy: userID, campus: campus, zone: zone,
                    leavingAt: leavingAt, expiresAt: leavingAt.addingTimeInterval(300),
                    status: .active, createdAt: now)
    }

    static func visible(_ signals: [Self], at now: Date) -> [Self] {
        signals.filter { !$0.status.isTerminal && $0.expiresAt > now }
            .sorted { $0.leavingAt == $1.leavingAt ? $0.id.uuidString < $1.id.uuidString : $0.leavingAt < $1.leavingAt }
    }

    func userState(for userID: UUID) -> UserState {
        switch status {
        case .active:
            return createdBy == userID ? .yourSignal : .available
        case .claimed:
            if createdBy == userID { return .someoneHeadingThere }
            if claimedBy == userID { return .youreHeadingThere }
            return .claimed
        case .arrived:
            if createdBy == userID { return .claimantArrived }
            if claimedBy == userID { return .youAreHere }
            return .handoverInProgress
        case .vacated:
            if claimedBy == userID { return .driverLeft }
            if createdBy == userID { return .waitingForClaimant }
            return .handoverInProgress
        case .completed, .unavailable, .cancelled, .expired:
            return .handoverInProgress
        }
    }

    func allowedActions(for userID: UUID) -> Set<LifecycleAction> {
        let isCreator = createdBy == userID
        let isClaimant = claimedBy == userID
        switch status {
        case .active:
            return isCreator ? [.cancel] : [.claim]
        case .claimed:
            if isCreator { return [.cancel] }
            if isClaimant { return [.release, .arrive, .showPass] }
        case .arrived:
            if isCreator { return [.cancel, .vacate] }
            if isClaimant { return [.release, .showPass] }
        case .vacated:
            if isClaimant { return [.complete, .unavailable, .showPass] }
        case .completed, .unavailable, .cancelled, .expired:
            break
        }
        return []
    }
}
