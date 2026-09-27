import CoreLocation
import Foundation

nonisolated struct ApproachPoint: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let capturedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated struct ApproachLocation: Codable, Equatable, Sendable {
    let signalID: UUID
    let owner: ApproachPoint
    let claimant: ApproachPoint?
    let claimantSharingEnabled: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case signalID = "signal_id"
        case ownerLatitude = "owner_latitude"
        case ownerLongitude = "owner_longitude"
        case ownerAccuracy = "owner_horizontal_accuracy"
        case ownerCapturedAt = "owner_captured_at"
        case claimantLatitude = "claimant_latitude"
        case claimantLongitude = "claimant_longitude"
        case claimantAccuracy = "claimant_horizontal_accuracy"
        case claimantCapturedAt = "claimant_captured_at"
        case claimantSharingEnabled = "claimant_sharing_enabled"
        case updatedAt = "updated_at"
    }

    init(signalID: UUID, owner: ApproachPoint, claimant: ApproachPoint?, claimantSharingEnabled: Bool, updatedAt: Date) {
        self.signalID = signalID
        self.owner = owner
        self.claimant = claimant
        self.claimantSharingEnabled = claimantSharingEnabled
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        signalID = try c.decode(UUID.self, forKey: .signalID)
        owner = ApproachPoint(
            latitude: try c.decode(Double.self, forKey: .ownerLatitude),
            longitude: try c.decode(Double.self, forKey: .ownerLongitude),
            horizontalAccuracy: try c.decode(Double.self, forKey: .ownerAccuracy),
            capturedAt: try c.decode(Date.self, forKey: .ownerCapturedAt)
        )
        let claimantLatitude = try c.decodeIfPresent(Double.self, forKey: .claimantLatitude)
        let claimantLongitude = try c.decodeIfPresent(Double.self, forKey: .claimantLongitude)
        let claimantAccuracy = try c.decodeIfPresent(Double.self, forKey: .claimantAccuracy)
        let claimantCapturedAt = try c.decodeIfPresent(Date.self, forKey: .claimantCapturedAt)
        let claimantParts: [Any?] = [claimantLatitude, claimantLongitude, claimantAccuracy, claimantCapturedAt]
        guard claimantParts.allSatisfy({ $0 == nil }) || claimantParts.allSatisfy({ $0 != nil }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .claimantLatitude, in: c,
                debugDescription: "Claimant approach coordinate is incomplete"
            )
        }
        if let latitude = claimantLatitude,
           let longitude = claimantLongitude,
           let accuracy = claimantAccuracy,
           let capturedAt = claimantCapturedAt {
            claimant = ApproachPoint(latitude: latitude, longitude: longitude, horizontalAccuracy: accuracy, capturedAt: capturedAt)
        } else {
            claimant = nil
        }
        claimantSharingEnabled = try c.decode(Bool.self, forKey: .claimantSharingEnabled)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        guard Self.isValid(owner), claimant.map(Self.isValid) ?? true else {
            throw DecodingError.dataCorruptedError(forKey: .ownerLatitude, in: c, debugDescription: "Invalid approach coordinate")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(signalID, forKey: .signalID)
        try c.encode(owner.latitude, forKey: .ownerLatitude)
        try c.encode(owner.longitude, forKey: .ownerLongitude)
        try c.encode(owner.horizontalAccuracy, forKey: .ownerAccuracy)
        try c.encode(owner.capturedAt, forKey: .ownerCapturedAt)
        try c.encodeIfPresent(claimant?.latitude, forKey: .claimantLatitude)
        try c.encodeIfPresent(claimant?.longitude, forKey: .claimantLongitude)
        try c.encodeIfPresent(claimant?.horizontalAccuracy, forKey: .claimantAccuracy)
        try c.encodeIfPresent(claimant?.capturedAt, forKey: .claimantCapturedAt)
        try c.encode(claimantSharingEnabled, forKey: .claimantSharingEnabled)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    private static func isValid(_ point: ApproachPoint) -> Bool {
        point.latitude.isFinite && point.longitude.isFinite && point.horizontalAccuracy.isFinite
            && (-90...90).contains(point.latitude) && (-180...180).contains(point.longitude)
            && (0...65).contains(point.horizontalAccuracy)
    }
}

nonisolated enum ApproachBand: String, Equatable, Sendable {
    case onTheWay = "On the way"
    case approaching = "Approaching"
    case nearby = "Nearby"
    case veryClose = "Very close"

    init(distance: Double) {
        if distance > 150 { self = .onTheWay }
        else if distance >= 50 { self = .approaching }
        else if distance >= 25 { self = .nearby }
        else { self = .veryClose }
    }
}

nonisolated enum ApproachFreshness: Equatable, Sendable {
    case waiting, active(seconds: Int), stale(seconds: Int), paused

    static func evaluate(location: ApproachLocation?, now: Date) -> Self {
        guard let location else { return .waiting }
        guard location.claimantSharingEnabled else { return .paused }
        guard let point = location.claimant else { return .waiting }
        let seconds = max(0, Int(now.timeIntervalSince(point.capturedAt)))
        return seconds <= 15 ? .active(seconds: seconds) : .stale(seconds: seconds)
    }

    var label: String {
        switch self {
        case .waiting: "Waiting for an accurate location"
        case .paused: "Location paused"
        case .active(let seconds): seconds < 2 ? "Updated just now" : "Updated \(seconds) sec ago"
        case .stale: "Location stale"
        }
    }
}

nonisolated protocol ApproachDistanceCalculating: Sendable {
    func distance(from: ApproachPoint, to: ApproachPoint) -> Double
}

nonisolated struct CoreLocationApproachDistanceCalculator: ApproachDistanceCalculating {
    func distance(from: ApproachPoint, to: ApproachPoint) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}

nonisolated enum ApproachReadingPolicy {
    static func accepts(_ reading: LocationReading, now: Date) -> Bool {
        CLLocationCoordinate2DIsValid(reading.coordinate)
            && reading.horizontalAccuracy.isFinite
            && (0...65).contains(reading.horizontalAccuracy)
            && abs(now.timeIntervalSince(reading.timestamp)) <= 15
    }

    static func shouldUpload(
        _ reading: LocationReading,
        after previous: ApproachPoint?,
        now: Date,
        distanceCalculator: any ApproachDistanceCalculating
    ) -> Bool {
        guard accepts(reading, now: now) else { return false }
        guard let previous else { return true }
        let current = ApproachPoint(
            latitude: reading.latitude, longitude: reading.longitude,
            horizontalAccuracy: reading.horizontalAccuracy, capturedAt: reading.timestamp
        )
        return reading.timestamp.timeIntervalSince(previous.capturedAt) >= 5
            || distanceCalculator.distance(from: previous, to: current) >= 15
    }
}
