import Foundation
import Supabase

@MainActor
protocol ParkingSignalRepository {
    func fetchFeed(now: Date) async throws -> SignalFeed
    func publish(_ request: PublishParkingSignalRequest) async throws -> ParkingSignal
    func claim(signalID: UUID, claimantVehicleID: UUID) async throws -> ParkingSignal
    func markArrived(signalID: UUID) async throws -> ParkingSignal
    func releaseClaim(signalID: UUID) async throws -> ParkingSignal
    func cancel(signalID: UUID) async throws -> ParkingSignal
    func markVacated(signalID: UUID) async throws -> ParkingSignal
    func complete(signalID: UUID) async throws -> ParkingSignal
    func markUnavailable(signalID: UUID) async throws -> ParkingSignal
    func observe(_ receive: @escaping @MainActor (SignalEvent) async -> Void) async throws
}

nonisolated struct PublishParkingSignalRequest: Equatable, Sendable {
    let signal: ParkingSignal
    let zoneID: String
    let ownerVehicleID: UUID
    let location: LocationReading
}

enum SignalEvent { case changed, connected, disconnected }

enum ParkingSignalRepositoryError: LocalizedError, Equatable {
    case activeSignalExists
    case signalUnavailable
    case transitionUnavailable
    case vehicleUnavailable
    case zoneUnavailable
    case locationUnavailable
    case locationInaccurate
    case outsideParkingZone
    case databaseSetupRequired
    case invalidSignalResponse

    var errorDescription: String? {
        switch self {
        case .activeSignalExists: "You already have an open parking signal. Finish or cancel it before publishing another."
        case .signalUnavailable: "This signal was already claimed or is no longer available."
        case .transitionUnavailable: "This action is no longer available. Refresh to see the latest signal."
        case .vehicleUnavailable: "Select a saved vehicle that belongs to this account."
        case .zoneUnavailable: "The selected parking zone is unavailable."
        case .locationUnavailable: "A valid current location is unavailable. Try again."
        case .locationInaccurate: "GPS accuracy must improve to 65 metres or better."
        case .outsideParkingZone: "You must be inside the selected student parking area to publish."
        case .databaseSetupRequired:
            "Supabase database update required. Run the pending ordered migrations through 202609250004_enforce_one_open_signal_per_creator.sql, then restart SpotSoon."
        case .invalidSignalResponse: "The server returned an invalid parking signal."
        }
    }
}

@MainActor
final class SupabaseParkingSignalRepository: ParkingSignalRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func fetchFeed(now: Date) async throws -> SignalFeed {
        do {
            try await client.rpc("expire_parking_signals").execute()
            let signals: [ParkingSignal] = try await client.from("parking_signals").select()
                .in("status", values: ["active", "claimed", "arrived", "vacated"])
                .gt("expires_at", value: now.ISO8601Format())
                .order("leaving_at", ascending: true).execute().value
            let details: [HandoverDetails] = try await client
                .from("parking_signal_handovers")
                .select()
                .execute()
                .value
            return SignalFeed(
                signals: signals,
                handoverDetails: Dictionary(uniqueKeysWithValues: details.map { ($0.signalID, $0) })
            )
        } catch let error as PostgrestError {
            throw translated(error)
        }
    }

    func publish(_ request: PublishParkingSignalRequest) async throws -> ParkingSignal {
        do {
            let response: SignalResponse = try await client
                .rpc("publish_parking_signal", params: PublishParameters(request: request))
                .execute()
                .value
            return response.signal
        } catch let error as PostgrestError {
            throw translated(error)
        }
    }

    func claim(signalID: UUID, claimantVehicleID: UUID) async throws -> ParkingSignal {
        do {
            let response: SignalResponse = try await client
                .rpc("claim_parking_signal", params: ClaimParameters(
                    pSignalID: signalID,
                    claimantVehicleID: claimantVehicleID
                ))
                .execute()
                .value
            return response.signal
        } catch let error as PostgrestError {
            throw translated(error)
        }
    }

    func markArrived(signalID: UUID) async throws -> ParkingSignal {
        try await callLifecycleRPC("arrive_at_parking_signal", signalID: signalID)
    }

    func releaseClaim(signalID: UUID) async throws -> ParkingSignal {
        try await callLifecycleRPC("release_parking_signal", signalID: signalID)
    }

    func cancel(signalID: UUID) async throws -> ParkingSignal {
        try await callLifecycleRPC("cancel_parking_signal", signalID: signalID)
    }

    func markVacated(signalID: UUID) async throws -> ParkingSignal {
        try await callLifecycleRPC("vacate_parking_signal", signalID: signalID)
    }

    func complete(signalID: UUID) async throws -> ParkingSignal {
        try await callLifecycleRPC("complete_parking_signal", signalID: signalID)
    }

    func markUnavailable(signalID: UUID) async throws -> ParkingSignal {
        try await callLifecycleRPC("mark_parking_signal_unavailable", signalID: signalID)
    }

    private func callLifecycleRPC(_ name: String, signalID: UUID) async throws -> ParkingSignal {
        do {
            let response: SignalResponse = try await client
                .rpc(name, params: SignalIDParameters(pSignalID: signalID))
                .execute()
                .value
            return response.signal
        } catch let error as PostgrestError {
            throw translated(error)
        }
    }

    private func translated(_ error: PostgrestError) -> any Error {
        let diagnostic = [error.code, error.message, error.details, error.hint]
            .compactMap { $0 }
            .joined(separator: " ")
        return Self.repositoryError(for: diagnostic) ?? error
    }

    nonisolated static func repositoryError(for diagnostic: String) -> ParkingSignalRepositoryError? {
        let diagnostic = diagnostic.lowercased()
        if diagnostic.contains("active_signal_exists")
            || diagnostic.contains("parking_signals_one_open_per_creator_idx") {
            return .activeSignalExists
        }
        if diagnostic.contains("signal_unavailable") {
            return .signalUnavailable
        }
        if diagnostic.contains("transition_unavailable") {
            return .transitionUnavailable
        }
        if diagnostic.contains("vehicle_unavailable") {
            return .vehicleUnavailable
        }
        if diagnostic.contains("zone_unavailable") {
            return .zoneUnavailable
        }
        if diagnostic.contains("location_unavailable") {
            return .locationUnavailable
        }
        if diagnostic.contains("location_inaccurate") {
            return .locationInaccurate
        }
        if diagnostic.contains("outside_parking_zone") {
            return .outsideParkingZone
        }
        if diagnostic.contains("pgrst202")
            || diagnostic.contains("expire_parking_signals") {
            return .databaseSetupRequired
        }
        return nil
    }

    // The store owns one observation task. Cancellation tears down both streams and the channel.
    func observe(_ receive: @escaping @MainActor (SignalEvent) async -> Void) async throws {
        let channel = client.channel("parking-signals-\(UUID().uuidString)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "parking_signals")
        let statuses = channel.statusChange
        let connectionStatuses = client.realtimeV2.statusChange
        do {
            try await channel.subscribeWithError()
            try Task.checkCancellation()
            await receive(.connected)
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in changes {
                        guard !Task.isCancelled else { break }
                        await receive(.changed)
                    }
                }
                group.addTask {
                    for await status in statuses {
                        guard !Task.isCancelled else { break }
                        switch status {
                        case .subscribed: await receive(.connected)
                        case .unsubscribed, .unsubscribing: await receive(.disconnected)
                        case .subscribing: await receive(.disconnected)
                        }
                    }
                }
                group.addTask {
                    for await status in connectionStatuses {
                        guard !Task.isCancelled else { break }
                        if status == .disconnected {
                            await receive(.disconnected)
                        } else if status == .connected, channel.status == .subscribed {
                            await receive(.connected)
                        }
                    }
                }
                await group.waitForAll()
            }
            await client.removeChannel(channel)
        } catch {
            await client.removeChannel(channel)
            throw error
        }
    }
}

private struct PublishParameters: Encodable {
    let zoneID: String
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let leavingAt: Date
    let expiresAt: Date
    let ownerVehicleID: UUID

    init(request: PublishParkingSignalRequest) {
        zoneID = request.zoneID
        latitude = request.location.latitude
        longitude = request.location.longitude
        horizontalAccuracy = request.location.horizontalAccuracy
        leavingAt = request.signal.leavingAt
        expiresAt = request.signal.expiresAt
        ownerVehicleID = request.ownerVehicleID
    }

    enum CodingKeys: String, CodingKey {
        case zoneID = "p_zone_id"
        case latitude = "p_device_latitude"
        case longitude = "p_device_longitude"
        case horizontalAccuracy = "p_horizontal_accuracy"
        case leavingAt = "p_leaving_at"
        case expiresAt = "p_expires_at"
        case ownerVehicleID = "p_owner_vehicle_id"
    }
}

private struct ClaimParameters: Encodable {
    let pSignalID: UUID
    let claimantVehicleID: UUID

    enum CodingKeys: String, CodingKey {
        case pSignalID = "p_signal_id"
        case claimantVehicleID = "p_claimant_vehicle_id"
    }
}

private struct SignalIDParameters: Encodable {
    let pSignalID: UUID

    enum CodingKeys: String, CodingKey {
        case pSignalID = "p_signal_id"
    }
}

private struct SignalResponse: Decodable {
    let signal: ParkingSignal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let signal = try? container.decode(ParkingSignal.self) {
            self.signal = signal
            return
        }
        let signals = try container.decode([ParkingSignal].self)
        guard signals.count == 1, let signal = signals.first else {
            throw ParkingSignalRepositoryError.invalidSignalResponse
        }
        self.signal = signal
    }
}
