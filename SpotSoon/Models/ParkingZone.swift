import CoreLocation
import Foundation

nonisolated struct ParkingZone: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let campus: ParkingSignal.Campus
    let landmark: String
    let latitude: Double
    let longitude: Double
    let verificationRadiusMeters: Double
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, campus, landmark, latitude, longitude
        case verificationRadiusMeters = "verification_radius_meters"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isSupported: Bool { id == Self.campusAStudent.id }

    static let campusAStudent = ParkingZone(
        id: "campus_a_student",
        name: "Campus A Student Car Park",
        campus: .campusA,
        landmark: "West of the stadium",
        latitude: 26.164736,
        longitude: 50.543676,
        verificationRadiusMeters: 140,
        isActive: true,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
}

nonisolated struct LocationReading: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
