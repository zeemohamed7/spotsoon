import Foundation

nonisolated struct Vehicle: Codable, Identifiable, Equatable, Sendable {
    enum VehicleType: String, Codable, CaseIterable, Sendable {
        case sedan, suv, hatchback, pickup, van, other

        var title: String {
            switch self {
            case .sedan: "Sedan"
            case .suv: "SUV"
            case .hatchback: "Hatchback"
            case .pickup: "Pickup"
            case .van: "Van"
            case .other: "Other"
            }
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: raw) ?? .other
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    let id: UUID
    let userID: UUID
    let nickname: String
    let color: String
    let vehicleType: VehicleType
    let make: String?
    let model: String?
    let plateSuffix: String?
    let isCurrent: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, nickname, color, make, model
        case userID = "user_id"
        case vehicleType = "vehicle_type"
        case plateSuffix = "plate_suffix"
        case isCurrent = "is_current"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID,
        userID: UUID,
        nickname: String,
        color: String,
        vehicleType: VehicleType,
        make: String? = nil,
        model: String? = nil,
        plateSuffix: String? = nil,
        isCurrent: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userID = userID
        self.nickname = nickname
        self.color = color
        self.vehicleType = vehicleType
        self.make = make
        self.model = model
        self.plateSuffix = plateSuffix
        self.isCurrent = isCurrent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        nickname = try container.decode(String.self, forKey: .nickname)
        color = try container.decode(String.self, forKey: .color)
        let rawType = try container.decode(String.self, forKey: .vehicleType)
        vehicleType = VehicleType(rawValue: rawType) ?? .other
        make = try container.decodeIfPresent(String.self, forKey: .make)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        plateSuffix = try container.decodeIfPresent(String.self, forKey: .plateSuffix)
        isCurrent = try container.decode(Bool.self, forKey: .isCurrent)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(color, forKey: .color)
        try container.encode(vehicleType.rawValue, forKey: .vehicleType)
        try container.encodeIfPresent(make, forKey: .make)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(plateSuffix, forKey: .plateSuffix)
        try container.encode(isCurrent, forKey: .isCurrent)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var summary: String {
        VehicleSnapshot(
            nickname: nickname,
            color: color,
            vehicleType: vehicleType,
            make: make,
            model: model,
            plateSuffix: plateSuffix
        ).description
    }
}

nonisolated struct VehicleDraft: Equatable, Sendable {
    static let maximumNameLength = 40
    static let maximumColorLength = 30
    static let maximumMakeModelLength = 40

    var nickname = ""
    var color = ""
    var vehicleType: Vehicle.VehicleType = .sedan
    var make = ""
    var model = ""
    var plateSuffix = ""
    var useAsCurrent = false

    init() {}

    init(vehicle: Vehicle) {
        nickname = vehicle.nickname
        color = vehicle.color
        vehicleType = vehicle.vehicleType
        make = vehicle.make ?? ""
        model = vehicle.model ?? ""
        plateSuffix = vehicle.plateSuffix ?? ""
        useAsCurrent = vehicle.isCurrent
    }

    func validated() throws -> ValidatedVehicle {
        let nickname = try Self.trimmedRequired(self.nickname, maximum: Self.maximumNameLength, error: .invalidNickname)
        let color = try Self.trimmedRequired(self.color, maximum: Self.maximumColorLength, error: .invalidColor)
        let make = try optionalText(self.make, maximum: Self.maximumMakeModelLength)
        let model = try optionalText(self.model, maximum: Self.maximumMakeModelLength)
        let plate = plateSuffix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard plate.count <= 3,
              plate.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }) else {
            throw ValidationError.invalidPlateSuffix
        }
        return ValidatedVehicle(
            nickname: nickname,
            color: color,
            vehicleType: vehicleType,
            make: make,
            model: model,
            plateSuffix: plate.isEmpty ? nil : plate,
            useAsCurrent: useAsCurrent
        )
    }

    private static func trimmedRequired(_ value: String, maximum: Int, error: ValidationError) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximum else { throw error }
        return trimmed
    }

    private func optionalText(_ value: String, maximum: Int) throws -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maximum else { throw ValidationError.textTooLong }
        return trimmed.isEmpty ? nil : trimmed
    }

    enum ValidationError: LocalizedError, Equatable {
        case invalidNickname, invalidColor, invalidPlateSuffix, textTooLong

        var errorDescription: String? {
            switch self {
            case .invalidNickname: "Enter a nickname using 40 characters or fewer."
            case .invalidColor: "Enter a colour using 30 characters or fewer."
            case .invalidPlateSuffix: "Plate suffix must be one to three letters or numbers."
            case .textTooLong: "Make and model must each use 40 characters or fewer."
            }
        }
    }
}

nonisolated struct ValidatedVehicle: Equatable, Sendable {
    let nickname: String
    let color: String
    let vehicleType: Vehicle.VehicleType
    let make: String?
    let model: String?
    let plateSuffix: String?
    let useAsCurrent: Bool
}

nonisolated struct VehicleSnapshot: Codable, Equatable, Sendable {
    let nickname: String
    let color: String
    let vehicleType: Vehicle.VehicleType
    let make: String?
    let model: String?
    let plateSuffix: String?

    var description: String {
        var components = [color]
        if let make { components.append(make) }
        if let model { components.append(model) }
        components.append(vehicleType.title)
        var value = components.joined(separator: " ")
        if let plateSuffix { value += " · Plate ending \(plateSuffix)" }
        return value
    }
}
