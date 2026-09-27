import Foundation
import Supabase

@MainActor
protocol ApproachTrackingRepository {
    func fetch(signalID: UUID) async throws -> ApproachLocation?
    func setSharing(signalID: UUID, enabled: Bool) async throws -> ApproachLocation
    func update(signalID: UUID, reading: LocationReading) async throws -> ApproachLocation
}

enum ApproachTrackingRepositoryError: LocalizedError, Equatable {
    case unavailable, authenticationRequired, databaseSetupRequired, invalidResponse, invalidLocation

    var errorDescription: String? {
        switch self {
        case .unavailable: "Live approach sharing is no longer available for this handover."
        case .authenticationRequired: "Your private session ended. Reopen SpotSoon to continue."
        case .databaseSetupRequired: "Live approach tracking requires the pending Supabase migration."
        case .invalidResponse: "The server returned invalid live approach data."
        case .invalidLocation: "A fresh location with accuracy of 65 metres or better is required."
        }
    }
}

@MainActor
final class SupabaseApproachTrackingRepository: ApproachTrackingRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func fetch(signalID: UUID) async throws -> ApproachLocation? {
        do {
            let rows: [ApproachLocation] = try await client.from("parking_signal_locations")
                .select().eq("signal_id", value: signalID).limit(1).execute().value
            return rows.first
        } catch let error as PostgrestError {
            if let mapped = Self.repositoryError(for: Self.diagnostic(for: error)) { throw mapped }
            throw error
        }
    }

    func setSharing(signalID: UUID, enabled: Bool) async throws -> ApproachLocation {
        try await call("set_approach_location_sharing", params: SharingParameters(
            signalID: signalID, enabled: enabled
        ))
    }

    func update(signalID: UUID, reading: LocationReading) async throws -> ApproachLocation {
        try await call("update_claimant_approach_location", params: UpdateParameters(
            signalID: signalID, reading: reading
        ))
    }

    private func call<Parameters: Encodable>(_ name: String, params: Parameters) async throws -> ApproachLocation {
        do {
            let response: ApproachResponse = try await client.rpc(name, params: params).execute().value
            return response.location
        } catch let error as PostgrestError {
            if let mapped = Self.repositoryError(for: Self.diagnostic(for: error)) { throw mapped }
            throw error
        }
    }

    nonisolated static func repositoryError(for diagnostic: String) -> ApproachTrackingRepositoryError? {
        let diagnostic = diagnostic.lowercased()
        if diagnostic.contains("authentication_required") || diagnostic.contains("jwt") {
            return .authenticationRequired
        }
        if diagnostic.contains("approach_unavailable") { return .unavailable }
        if diagnostic.contains("invalid_approach_location") { return .invalidLocation }
        if diagnostic.contains("parking_signal_locations")
            || diagnostic.contains("set_approach_location_sharing")
            || diagnostic.contains("update_claimant_approach_location") {
            return .databaseSetupRequired
        }
        return nil
    }

    private nonisolated static func diagnostic(for error: PostgrestError) -> String {
        [error.code, error.message, error.details, error.hint]
            .compactMap { $0 }.joined(separator: " ")
    }
}

private struct SharingParameters: Encodable {
    let signalID: UUID
    let enabled: Bool
    enum CodingKeys: String, CodingKey { case signalID = "p_signal_id"; case enabled = "p_enabled" }
}

private struct UpdateParameters: Encodable {
    let signalID: UUID
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let capturedAt: Date

    init(signalID: UUID, reading: LocationReading) {
        self.signalID = signalID
        latitude = reading.latitude
        longitude = reading.longitude
        horizontalAccuracy = reading.horizontalAccuracy
        capturedAt = reading.timestamp
    }
    enum CodingKeys: String, CodingKey {
        case signalID = "p_signal_id"
        case latitude = "p_latitude"
        case longitude = "p_longitude"
        case horizontalAccuracy = "p_horizontal_accuracy"
        case capturedAt = "p_captured_at"
    }
}

private struct ApproachResponse: Decodable {
    let location: ApproachLocation
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let row = try? container.decode(ApproachLocation.self) { location = row; return }
        let rows = try container.decode([ApproachLocation].self)
        guard rows.count == 1, let row = rows.first else { throw ApproachTrackingRepositoryError.invalidResponse }
        location = row
    }
}
