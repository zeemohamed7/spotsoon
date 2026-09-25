import CoreLocation
import Foundation

nonisolated enum ZoneVerificationFailure: LocalizedError, Equatable, Sendable {
    case unknownZone
    case inactiveZone
    case invalidLocation
    case staleLocation
    case inaccurateLocation
    case outsideZone

    var errorDescription: String? {
        switch self {
        case .unknownZone: "The selected parking zone is unavailable."
        case .inactiveZone: "This parking zone is not currently active."
        case .invalidLocation: "A valid location reading is unavailable."
        case .staleLocation: "Your location is out of date. Try again."
        case .inaccurateLocation: "GPS accuracy must improve to 65 metres or better."
        case .outsideZone: "You are outside the Campus A Student Car Park verification area."
        }
    }
}

nonisolated struct ZoneVerificationResult: Equatable, Sendable {
    let distanceMeters: Double?
    let horizontalAccuracy: Double
    let accepted: Bool
    let failure: ZoneVerificationFailure?
}

nonisolated struct ZoneVerifier: Sendable {
    let maximumReadingAge: TimeInterval
    let maximumAccuracy: Double
    let maximumBoundaryTolerance: Double

    init(
        maximumReadingAge: TimeInterval = 15,
        maximumAccuracy: Double = 65,
        maximumBoundaryTolerance: Double = 25
    ) {
        self.maximumReadingAge = maximumReadingAge
        self.maximumAccuracy = maximumAccuracy
        self.maximumBoundaryTolerance = maximumBoundaryTolerance
    }

    func verify(zone: ParkingZone?, reading: LocationReading, now: Date = .now) -> ZoneVerificationResult {
        guard let zone else { return failure(.unknownZone, accuracy: reading.horizontalAccuracy) }
        guard zone.isActive else { return failure(.inactiveZone, accuracy: reading.horizontalAccuracy) }
        guard CLLocationCoordinate2DIsValid(reading.coordinate),
              reading.latitude.isFinite,
              reading.longitude.isFinite,
              reading.horizontalAccuracy.isFinite,
              reading.horizontalAccuracy >= 0 else {
            return failure(.invalidLocation, accuracy: reading.horizontalAccuracy)
        }
        guard abs(now.timeIntervalSince(reading.timestamp)) <= maximumReadingAge else {
            return failure(.staleLocation, accuracy: reading.horizontalAccuracy)
        }
        guard reading.horizontalAccuracy <= maximumAccuracy else {
            return failure(.inaccurateLocation, accuracy: reading.horizontalAccuracy)
        }

        let centre = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
        let device = CLLocation(latitude: reading.latitude, longitude: reading.longitude)
        let distance = device.distance(from: centre)
        let tolerance = min(reading.horizontalAccuracy, maximumBoundaryTolerance)
        guard distance <= zone.verificationRadiusMeters + tolerance else {
            return ZoneVerificationResult(
                distanceMeters: distance,
                horizontalAccuracy: reading.horizontalAccuracy,
                accepted: false,
                failure: .outsideZone
            )
        }
        return ZoneVerificationResult(
            distanceMeters: distance,
            horizontalAccuracy: reading.horizontalAccuracy,
            accepted: true,
            failure: nil
        )
    }

    private func failure(_ reason: ZoneVerificationFailure, accuracy: Double) -> ZoneVerificationResult {
        ZoneVerificationResult(
            distanceMeters: nil,
            horizontalAccuracy: accuracy,
            accepted: false,
            failure: reason
        )
    }
}
