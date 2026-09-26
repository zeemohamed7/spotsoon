import Foundation

nonisolated struct HandoverRoute: Identifiable, Equatable, Sendable {
    let signalID: UUID
    var id: UUID { signalID }
}

nonisolated struct HandoverNavigationState: Equatable, Sendable {
    var pendingClaimRoute: HandoverRoute?
    var liveRoute: HandoverRoute?

    mutating func claimSucceeded(signalID: UUID) {
        pendingClaimRoute = HandoverRoute(signalID: signalID)
    }

    mutating func claimSheetDismissed() {
        guard let pendingClaimRoute else { return }
        self.pendingClaimRoute = nil
        liveRoute = pendingClaimRoute
    }

    mutating func resume(signalID: UUID) {
        liveRoute = HandoverRoute(signalID: signalID)
    }

    mutating func closeLiveHandover() {
        liveRoute = nil
    }

    static func restorableClaimantSignal(
        in signals: [ParkingSignal],
        userID: UUID,
        now: Date
    ) -> ParkingSignal? {
        ParkingSignal.visible(signals, at: now).first {
            $0.claimedBy == userID && [.claimed, .arrived, .vacated].contains($0.status)
        }
    }
}

nonisolated struct HandoverPassPresentationState: Equatable, Sendable {
    private(set) var isPresented = false

    mutating func show() { isPresented = true }
    mutating func close() { isPresented = false }
}

nonisolated enum CompactSignalAction: Equatable, Sendable {
    case claim
    case resumeHandover
    case none
}

nonisolated extension ParkingSignal {
    func compactAction(for userID: UUID) -> CompactSignalAction {
        if status == .active, createdBy != userID { return .claim }
        if claimedBy == userID, [.claimed, .arrived, .vacated].contains(status) {
            return .resumeHandover
        }
        return .none
    }
}
