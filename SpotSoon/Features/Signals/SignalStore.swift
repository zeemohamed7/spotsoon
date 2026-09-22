import Foundation
import Observation

@MainActor @Observable
final class SignalStore {
    private(set) var signals: [ParkingSignal] = []
    private(set) var isLoading = false
    private(set) var isPublishing = false
    private(set) var claimingSignalIDs: Set<UUID> = []
    var listError: String?
    var connectionError: String?
    var publishError: String?
    private(set) var claimErrors: [UUID: String] = [:]
    let userID: UUID
    private let repository: any ParkingSignalRepository
    private var observationTask: Task<Void, Never>?
    private var refreshVersion = 0

    init(repository: any ParkingSignalRepository, userID: UUID) {
        self.repository = repository
        self.userID = userID
    }

    func refresh(now: Date = .now) async {
        refreshVersion += 1
        let version = refreshVersion
        isLoading = true
        do {
            let fetched = try await repository.fetchActive(now: now)
            guard version == refreshVersion else { return }
            signals = ParkingSignal.visible(fetched, at: now)
            listError = nil
        } catch {
            guard version == refreshVersion else { return }
            if !Task.isCancelled { listError = "Could not load signals: \(error.localizedDescription)" }
        }
        if version == refreshVersion { isLoading = false }
    }

    func run() async {
        // Await cleanup before replacing a subscription, including rapid scene/retry changes.
        let previous = observationTask
        previous?.cancel()
        await previous?.value
        guard !Task.isCancelled else { return }
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.refresh() }
                group.addTask { await self.observe() }
                await group.waitForAll()
            }
        }
        observationTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func observe() async {
        do {
            try await repository.observe { [weak self] event in
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .connected:
                    self.connectionError = nil
                    await self.refresh() // Reconcile missed changes after connection/reconnection.
                case .changed: await self.refresh()
                case .disconnected:
                    self.connectionError = "Live updates disconnected. Use Refresh or Retry live updates."
                }
            }
        } catch {
            if !Task.isCancelled { connectionError = "Live updates failed: \(error.localizedDescription)" }
        }
    }

    func publish(campus: ParkingSignal.Campus, zone: String, minutes: Int, now: Date = .now) async -> Bool {
        guard !isPublishing else { return false }
        guard campus.zones.contains(zone), [2, 5, 10].contains(minutes) else {
            publishError = "Choose a valid zone and leaving time."
            return false
        }
        isPublishing = true
        publishError = nil
        defer { isPublishing = false }
        do {
            let signal = ParkingSignal.leaving(userID: userID, campus: campus, zone: zone, minutes: minutes, now: now)
            try await repository.insert(signal)
            await refresh()
            return true
        } catch {
            publishError = "Could not publish signal: \(error.localizedDescription)"
            return false
        }
    }

    func claim(_ signal: ParkingSignal, now: Date = .now) async -> Bool {
        guard signal.status == .active, signal.createdBy != userID else { return false }
        guard claimingSignalIDs.insert(signal.id).inserted else { return false }
        claimErrors[signal.id] = nil
        defer { claimingSignalIDs.remove(signal.id) }

        do {
            let claimed = try await repository.claim(signalID: signal.id)
            guard claimed.id == signal.id else {
                throw ParkingSignalRepositoryError.invalidClaimResponse
            }
            if let index = signals.firstIndex(where: { $0.id == claimed.id }) {
                signals[index] = claimed
            } else {
                signals.append(claimed)
            }
            signals = ParkingSignal.visible(signals, at: now)
            return true
        } catch {
            if let repositoryError = error as? ParkingSignalRepositoryError,
               repositoryError == .signalUnavailable {
                claimErrors[signal.id] = "This signal was already claimed or is no longer available."
            } else {
                claimErrors[signal.id] = "Could not claim signal: \(error.localizedDescription)"
            }
            await refresh()
            return false
        }
    }

    func isClaiming(_ signalID: UUID) -> Bool {
        claimingSignalIDs.contains(signalID)
    }
}
