import Foundation

nonisolated struct ParkingSignal: Codable, Identifiable, Equatable, Sendable {
    enum Campus: String, Codable, CaseIterable, Sendable {
        case campusA = "campus_a", campusB = "campus_b"
        var title: String { self == .campusA ? "Campus A" : "Campus B" }
        var zones: [String] { self == .campusA ? ["A1", "A2", "A3"] : ["B1", "B2", "B3"] }
    }
    enum Status: String, Codable, Sendable { case active, cancelled, expired }

    let id: UUID
    let createdBy: UUID
    let campus: Campus
    let zone: String
    let leavingAt: Date
    let expiresAt: Date
    let status: Status
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, campus, zone, status
        case createdBy = "created_by", leavingAt = "leaving_at"
        case expiresAt = "expires_at", createdAt = "created_at"
    }

    static func leaving(userID: UUID, campus: Campus, zone: String, minutes: Int, now: Date) -> Self {
        let leavingAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        return Self(id: UUID(), createdBy: userID, campus: campus, zone: zone,
                    leavingAt: leavingAt, expiresAt: leavingAt.addingTimeInterval(300),
                    status: .active, createdAt: now)
    }

    static func active(_ signals: [Self], at now: Date) -> [Self] {
        signals.filter { $0.status == .active && $0.expiresAt > now }
            .sorted { $0.leavingAt == $1.leavingAt ? $0.id.uuidString < $1.id.uuidString : $0.leavingAt < $1.leavingAt }
    }
}
