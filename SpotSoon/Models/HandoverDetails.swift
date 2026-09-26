import Foundation

nonisolated struct HandoverDetails: Codable, Identifiable, Equatable, Sendable {
    enum PassColor: String, Codable, Sendable {
        case red, orange, yellow, green, blue, purple
        var title: String { rawValue.capitalized }
    }

    struct Pass: Equatable, Sendable {
        let color: PassColor
        let symbolName: String
        let confirmationNumber: String

        var animalName: String {
            switch symbolName {
            case "hare.fill": "Hare"
            case "tortoise.fill": "Tortoise"
            case "bird.fill": "Bird"
            case "fish.fill": "Fish"
            case "ladybug.fill": "Ladybug"
            default: "Fox"
            }
        }

        var title: String { "\(color.title) \(animalName) · \(confirmationNumber)" }
    }

    let signalID: UUID
    let passColor: PassColor?
    let symbolName: String?
    let confirmationNumber: String?
    let parkingHint: String?
    let ownerVehicle: VehicleSnapshot
    let claimantVehicle: VehicleSnapshot?
    let createdAt: Date

    var id: UUID { signalID }

    var pass: Pass? {
        guard let passColor, let symbolName, let confirmationNumber else { return nil }
        return Pass(color: passColor, symbolName: symbolName, confirmationNumber: confirmationNumber)
    }

    enum CodingKeys: String, CodingKey {
        case signalID = "signal_id"
        case passColor = "pass_color"
        case symbolName = "symbol_name"
        case confirmationNumber = "confirmation_number"
        case parkingHint = "parking_hint"
        case ownerNickname = "owner_nickname"
        case ownerColor = "owner_color"
        case ownerVehicleType = "owner_vehicle_type"
        case ownerMake = "owner_make"
        case ownerModel = "owner_model"
        case ownerPlateSuffix = "owner_plate_suffix"
        case claimantNickname = "claimant_nickname"
        case claimantColor = "claimant_color"
        case claimantVehicleType = "claimant_vehicle_type"
        case claimantMake = "claimant_make"
        case claimantModel = "claimant_model"
        case claimantPlateSuffix = "claimant_plate_suffix"
        case createdAt = "created_at"
    }

    init(
        signalID: UUID,
        passColor: PassColor?,
        symbolName: String?,
        confirmationNumber: String?,
        ownerVehicle: VehicleSnapshot,
        claimantVehicle: VehicleSnapshot?,
        parkingHint: String? = nil,
        createdAt: Date
    ) {
        self.signalID = signalID
        self.passColor = passColor
        self.symbolName = symbolName
        self.confirmationNumber = confirmationNumber
        self.parkingHint = parkingHint
        self.ownerVehicle = ownerVehicle
        self.claimantVehicle = claimantVehicle
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signalID = try container.decode(UUID.self, forKey: .signalID)
        passColor = try container.decodeIfPresent(PassColor.self, forKey: .passColor)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName)
        confirmationNumber = try container.decodeIfPresent(String.self, forKey: .confirmationNumber)
        parkingHint = try container.decodeIfPresent(String.self, forKey: .parkingHint)
        ownerVehicle = VehicleSnapshot(
            nickname: try container.decode(String.self, forKey: .ownerNickname),
            color: try container.decode(String.self, forKey: .ownerColor),
            vehicleType: try container.decode(Vehicle.VehicleType.self, forKey: .ownerVehicleType),
            make: try container.decodeIfPresent(String.self, forKey: .ownerMake),
            model: try container.decodeIfPresent(String.self, forKey: .ownerModel),
            plateSuffix: try container.decodeIfPresent(String.self, forKey: .ownerPlateSuffix)
        )
        if let nickname = try container.decodeIfPresent(String.self, forKey: .claimantNickname),
           let color = try container.decodeIfPresent(String.self, forKey: .claimantColor),
           let type = try container.decodeIfPresent(Vehicle.VehicleType.self, forKey: .claimantVehicleType) {
            claimantVehicle = VehicleSnapshot(
                nickname: nickname,
                color: color,
                vehicleType: type,
                make: try container.decodeIfPresent(String.self, forKey: .claimantMake),
                model: try container.decodeIfPresent(String.self, forKey: .claimantModel),
                plateSuffix: try container.decodeIfPresent(String.self, forKey: .claimantPlateSuffix)
            )
        } else {
            claimantVehicle = nil
        }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signalID, forKey: .signalID)
        try container.encodeIfPresent(passColor, forKey: .passColor)
        try container.encodeIfPresent(symbolName, forKey: .symbolName)
        try container.encodeIfPresent(confirmationNumber, forKey: .confirmationNumber)
        try container.encodeIfPresent(parkingHint, forKey: .parkingHint)
        try container.encode(ownerVehicle.nickname, forKey: .ownerNickname)
        try container.encode(ownerVehicle.color, forKey: .ownerColor)
        try container.encode(ownerVehicle.vehicleType, forKey: .ownerVehicleType)
        try container.encodeIfPresent(ownerVehicle.make, forKey: .ownerMake)
        try container.encodeIfPresent(ownerVehicle.model, forKey: .ownerModel)
        try container.encodeIfPresent(ownerVehicle.plateSuffix, forKey: .ownerPlateSuffix)
        try container.encodeIfPresent(claimantVehicle?.nickname, forKey: .claimantNickname)
        try container.encodeIfPresent(claimantVehicle?.color, forKey: .claimantColor)
        try container.encodeIfPresent(claimantVehicle?.vehicleType, forKey: .claimantVehicleType)
        try container.encodeIfPresent(claimantVehicle?.make, forKey: .claimantMake)
        try container.encodeIfPresent(claimantVehicle?.model, forKey: .claimantModel)
        try container.encodeIfPresent(claimantVehicle?.plateSuffix, forKey: .claimantPlateSuffix)
        try container.encode(createdAt, forKey: .createdAt)
    }

    func counterpartVehicle(for signal: ParkingSignal, userID: UUID) -> VehicleSnapshot? {
        if signal.createdBy == userID { return claimantVehicle }
        if signal.claimedBy == userID { return ownerVehicle }
        return nil
    }
}

nonisolated struct SignalFeed: Equatable, Sendable {
    let signals: [ParkingSignal]
    let handoverDetails: [UUID: HandoverDetails]

    static let empty = SignalFeed(signals: [], handoverDetails: [:])
}
