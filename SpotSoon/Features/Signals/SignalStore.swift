import Foundation
import Observation

@MainActor @Observable
final class SignalStore {
    private(set) var signals: [ParkingSignal] = []
    private(set) var isLoading = false
    private(set) var isPublishing = false
    var listError: String?
    var connectionError: String?
    var publishError: String?
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
            signals = ParkingSignal.active(fetched, at: now)
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
}
