import Foundation
import Supabase

@MainActor
protocol ParkingSignalRepository {
    func fetchActive(now: Date) async throws -> [ParkingSignal]
    func insert(_ signal: ParkingSignal) async throws
    func observe(_ receive: @escaping @MainActor (SignalEvent) async -> Void) async throws
}

enum SignalEvent { case changed, connected, disconnected }

@MainActor
final class SupabaseParkingSignalRepository: ParkingSignalRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func fetchActive(now: Date) async throws -> [ParkingSignal] {
        try await client.from("parking_signals").select()
            .eq("status", value: "active")
            .gt("expires_at", value: now.ISO8601Format())
            .order("leaving_at", ascending: true).execute().value
    }

    func insert(_ signal: ParkingSignal) async throws {
        try await client.from("parking_signals").insert(signal).execute()
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
