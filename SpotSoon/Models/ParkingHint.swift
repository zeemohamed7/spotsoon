import Foundation

nonisolated enum ParkingHintValidationError: LocalizedError, Equatable, Sendable {
    case tooLong
    case invalidCharacters

    var errorDescription: String? {
        switch self {
        case .tooLong:
            "Parking hints must be 120 characters or fewer."
        case .invalidCharacters:
            "Parking hints cannot contain control characters."
        }
    }
}

nonisolated enum ParkingHint {
    static let maximumLength = 120

    static func normalize(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ParkingHintValidationError.invalidCharacters
        }
        guard trimmed.count <= maximumLength else {
            throw ParkingHintValidationError.tooLong
        }
        return trimmed
    }
}
