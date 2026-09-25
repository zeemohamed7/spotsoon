import Foundation
import Observation
import Supabase

@MainActor
protocol ParkingZoneRepository {
    func fetchActiveZones() async throws -> [ParkingZone]
}

@MainActor
protocol ParkingZoneSelectionPersisting: AnyObject {
    var selectedZoneID: String? { get set }
}

@MainActor
final class UserDefaultsParkingZoneSelection: ParkingZoneSelectionPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "selectedParkingZoneID") {
        self.defaults = defaults
        self.key = key
    }

    var selectedZoneID: String? {
        get { defaults.string(forKey: key) }
        set {
            if let newValue { defaults.set(newValue, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }
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
    private(set) var selectedZoneID: String?

    private let repository: any ParkingZoneRepository
    private let selectionPersistence: any ParkingZoneSelectionPersisting

    init(
        repository: any ParkingZoneRepository,
        selectionPersistence: (any ParkingZoneSelectionPersisting)? = nil
    ) {
        self.repository = repository
        let persistence = selectionPersistence ?? UserDefaultsParkingZoneSelection()
        self.selectionPersistence = persistence
        selectedZoneID = persistence.selectedZoneID
    }

    var selectedZone: ParkingZone? {
        guard let selectedZoneID else { return nil }
        return zones.first { $0.id == selectedZoneID && $0.isActive }
    }

    @discardableResult
    func selectZone(id: String) -> Bool {
        guard zones.contains(where: { $0.id == id && $0.isActive && $0.isSupported }) else {
            return false
        }
        selectedZoneID = id
        selectionPersistence.selectedZoneID = id
        return true
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await repository.fetchActiveZones()
            zones = fetched.filter { $0.isActive && $0.isSupported }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if selectedZone == nil {
                selectedZoneID = zones.first?.id
                selectionPersistence.selectedZoneID = selectedZoneID
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not load parking zones: \(error.localizedDescription)"
        }
    }
}
