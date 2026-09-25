import Foundation
import Observation

@MainActor @Observable
final class VehicleStore {
    private(set) var vehicles: [Vehicle] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var lastSavedVehicleID: UUID?
    private(set) var inFlightVehicleIDs: Set<UUID> = []
    var errorMessage: String?
    var editorError: String?

    let userID: UUID
    private let repository: any VehicleRepository
    private var loadVersion = 0

    init(repository: any VehicleRepository, userID: UUID) {
        self.repository = repository
        self.userID = userID
    }

    var currentVehicle: Vehicle? { vehicles.first(where: \.isCurrent) }

    func load() async {
        loadVersion += 1
        let version = loadVersion
        isLoading = true
        do {
            let rows = try await fetchEnsuringCurrentVehicle()
            guard version == loadVersion else { return }
            vehicles = rows
            errorMessage = nil
        } catch {
            guard version == loadVersion else { return }
            if !Task.isCancelled { errorMessage = "Could not load your garage: \(error.localizedDescription)" }
        }
        if version == loadVersion { isLoading = false }
    }

    func save(_ draft: VehicleDraft, editing vehicle: Vehicle? = nil) async -> Bool {
        guard !isSaving else { return false }
        let validated: ValidatedVehicle
        do {
            validated = try draft.validated()
        } catch {
            editorError = error.localizedDescription
            return false
        }

        isSaving = true
        editorError = nil
        lastSavedVehicleID = nil
        let original = vehicles
        defer { isSaving = false }
        do {
            let saved: Vehicle
            if let vehicle {
                saved = try await repository.update(id: vehicle.id, vehicle: validated)
                replace(saved)
            } else {
                saved = try await repository.create(validated, userID: userID)
                replace(saved)
            }

            if validated.useAsCurrent || (vehicle == nil && original.isEmpty) {
                let selected = try await repository.setCurrent(id: saved.id)
                markCurrent(selected)
            }
            lastSavedVehicleID = saved.id
            await reconcileAfterSuccess()
            return true
        } catch {
            vehicles = original
            lastSavedVehicleID = nil
            editorError = "Could not save vehicle: \(error.localizedDescription)"
            await refreshAfterFailure()
            return false
        }
    }

    func select(_ vehicle: Vehicle) async -> Bool {
        guard inFlightVehicleIDs.insert(vehicle.id).inserted else { return false }
        let original = vehicles
        errorMessage = nil
        defer { inFlightVehicleIDs.remove(vehicle.id) }
        do {
            let selected = try await repository.setCurrent(id: vehicle.id)
            markCurrent(selected)
            return true
        } catch {
            vehicles = original
            errorMessage = "Could not select Today’s Vehicle: \(error.localizedDescription)"
            await refreshAfterFailure()
            return false
        }
    }

    func delete(_ vehicle: Vehicle) async -> Bool {
        guard inFlightVehicleIDs.insert(vehicle.id).inserted else { return false }
        let original = vehicles
        errorMessage = nil
        vehicles.removeAll { $0.id == vehicle.id }
        defer { inFlightVehicleIDs.remove(vehicle.id) }
        do {
            try await repository.delete(id: vehicle.id)
            await reconcileAfterSuccess()
            return true
        } catch {
            vehicles = original
            errorMessage = "Could not delete vehicle: \(error.localizedDescription)"
            await refreshAfterFailure()
            return false
        }
    }

    func isWorking(on vehicleID: UUID) -> Bool { inFlightVehicleIDs.contains(vehicleID) }

    private func replace(_ vehicle: Vehicle) {
        if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index] = vehicle
        } else {
            vehicles.append(vehicle)
        }
        vehicles = Self.sorted(vehicles)
    }

    private func markCurrent(_ selected: Vehicle) {
        vehicles = Self.sorted(vehicles.map { vehicle in
            Vehicle(
                id: vehicle.id,
                userID: vehicle.userID,
                nickname: vehicle.nickname,
                color: vehicle.color,
                vehicleType: vehicle.vehicleType,
                make: vehicle.make,
                model: vehicle.model,
                plateSuffix: vehicle.plateSuffix,
                isCurrent: vehicle.id == selected.id,
                createdAt: vehicle.createdAt,
                updatedAt: vehicle.id == selected.id ? selected.updatedAt : vehicle.updatedAt
            )
        })
    }

    private func reconcileAfterSuccess() async {
        do {
            vehicles = try await fetchEnsuringCurrentVehicle()
            errorMessage = nil
        } catch {
            errorMessage = "Saved, but could not refresh your garage: \(error.localizedDescription)"
        }
    }

    private func refreshAfterFailure() async {
        do { vehicles = try await fetchEnsuringCurrentVehicle() } catch {}
    }

    /// The database trigger normally chooses a replacement after deletion.
    /// This reconciliation also heals rows created before that trigger existed
    /// and keeps the UI deterministic if a stale project schema omitted it.
    private func fetchEnsuringCurrentVehicle() async throws -> [Vehicle] {
        var rows = Self.sorted(try await repository.fetchVehicles())
        guard !rows.isEmpty, !rows.contains(where: \.isCurrent) else { return rows }

        _ = try await repository.setCurrent(id: rows[0].id)
        rows = Self.sorted(try await repository.fetchVehicles())
        return rows
    }

    private static func sorted(_ vehicles: [Vehicle]) -> [Vehicle] {
        vehicles.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
