import Foundation
import Observation
import Supabase

@MainActor
protocol ParkingZoneRepository {
    func fetchActiveZones() async throws -> [ParkingZone]
}

@MainActor
final class SupabaseParkingZoneRepository: ParkingZoneRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func fetchActiveZones() async throws -> [ParkingZone] {
        try await client.from("parking_zones")
            .select()
            .eq("is_active", value: true)
            .order("name", ascending: true)
            .execute()
            .value
    }
}

@MainActor @Observable
final class ParkingZoneStore {
    private(set) var zones: [ParkingZone] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var selectedZoneID: String?

    private let repository: any ParkingZoneRepository

    init(repository: any ParkingZoneRepository) {
        self.repository = repository
    }

    var selectedZone: ParkingZone? {
        guard let selectedZoneID else { return nil }
        return zones.first { $0.id == selectedZoneID && $0.isActive }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await repository.fetchActiveZones()
            zones = fetched.filter { $0.isActive && $0.isSupported }
            if selectedZone == nil { selectedZoneID = zones.first?.id }
            errorMessage = nil
        } catch {
            errorMessage = "Could not load parking zones: \(error.localizedDescription)"
        }
    }
}
