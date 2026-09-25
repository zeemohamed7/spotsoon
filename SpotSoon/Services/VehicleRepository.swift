import Foundation
import Supabase

@MainActor
protocol VehicleRepository {
    func fetchVehicles() async throws -> [Vehicle]
    func create(_ vehicle: ValidatedVehicle, userID: UUID) async throws -> Vehicle
    func update(id: UUID, vehicle: ValidatedVehicle) async throws -> Vehicle
    func delete(id: UUID) async throws
    func setCurrent(id: UUID) async throws -> Vehicle
}

enum VehicleRepositoryError: LocalizedError, Equatable {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: "That vehicle no longer exists or belongs to another account."
        case .invalidResponse: "The server returned an invalid vehicle."
        }
    }
}

@MainActor
final class SupabaseVehicleRepository: VehicleRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func fetchVehicles() async throws -> [Vehicle] {
        try await client.from("vehicles")
            .select()
            .order("is_current", ascending: false)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func create(_ vehicle: ValidatedVehicle, userID: UUID) async throws -> Vehicle {
        let rows: [Vehicle] = try await client.from("vehicles")
            .insert(VehicleInsert(userID: userID, vehicle: vehicle))
            .select()
            .execute()
            .value
        guard rows.count == 1, let row = rows.first else { throw VehicleRepositoryError.invalidResponse }
        return row
    }

    func update(id: UUID, vehicle: ValidatedVehicle) async throws -> Vehicle {
        let rows: [Vehicle] = try await client.from("vehicles")
            .update(VehicleUpdate(vehicle: vehicle))
            .eq("id", value: id)
            .select()
            .execute()
            .value
        guard rows.count == 1, let row = rows.first else { throw VehicleRepositoryError.unavailable }
        return row
    }

    func delete(id: UUID) async throws {
        try await client.from("vehicles").delete().eq("id", value: id).execute()
    }

    func setCurrent(id: UUID) async throws -> Vehicle {
        do {
            let response: VehicleResponse = try await client
                .rpc("set_current_vehicle", params: VehicleIDParameters(vehicleID: id))
                .execute()
                .value
            return response.vehicle
        } catch let error as PostgrestError {
            let diagnostic = [error.code, error.message, error.details, error.hint]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            if diagnostic.contains("vehicle_unavailable") { throw VehicleRepositoryError.unavailable }
            throw error
        }
    }
}

private struct VehicleInsert: Encodable {
    let userID: UUID
    let nickname: String
    let color: String
    let vehicleType: String
    let make: String?
    let model: String?
    let plateSuffix: String?
    let isCurrent = false

    init(userID: UUID, vehicle: ValidatedVehicle) {
        self.userID = userID
        nickname = vehicle.nickname
        color = vehicle.color
        vehicleType = vehicle.vehicleType.rawValue
        make = vehicle.make
        model = vehicle.model
        plateSuffix = vehicle.plateSuffix
    }

    enum CodingKeys: String, CodingKey {
        case nickname, color, make, model
        case userID = "user_id"
        case vehicleType = "vehicle_type"
        case plateSuffix = "plate_suffix"
        case isCurrent = "is_current"
    }
}

private struct VehicleUpdate: Encodable {
    let nickname: String
    let color: String
    let vehicleType: String
    let make: String?
    let model: String?
    let plateSuffix: String?

    init(vehicle: ValidatedVehicle) {
        nickname = vehicle.nickname
        color = vehicle.color
        vehicleType = vehicle.vehicleType.rawValue
        make = vehicle.make
        model = vehicle.model
        plateSuffix = vehicle.plateSuffix
    }

    enum CodingKeys: String, CodingKey {
        case nickname, color, make, model
        case vehicleType = "vehicle_type"
        case plateSuffix = "plate_suffix"
    }
}

private struct VehicleIDParameters: Encodable {
    let vehicleID: UUID
    enum CodingKeys: String, CodingKey { case vehicleID = "p_vehicle_id" }
}

private struct VehicleResponse: Decodable {
    let vehicle: Vehicle

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let vehicle = try? container.decode(Vehicle.self) {
            self.vehicle = vehicle
            return
        }
        let vehicles = try container.decode([Vehicle].self)
        guard vehicles.count == 1, let vehicle = vehicles.first else {
            throw VehicleRepositoryError.invalidResponse
        }
        self.vehicle = vehicle
    }
}
