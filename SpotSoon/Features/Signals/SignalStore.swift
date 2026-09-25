import Foundation
import Observation

@MainActor @Observable
final class SignalStore {
    private(set) var signals: [ParkingSignal] = []
    private(set) var handoverDetails: [UUID: HandoverDetails] = [:]
    private(set) var localBayHints: [UUID: String] = [:]
    private(set) var isLoading = false
    private(set) var isPublishing = false
    private(set) var inFlightSignalIDs: Set<UUID> = []
    var listError: String?
    var connectionError: String?
    var publishError: String?
    private(set) var publishRequiresLocationRefresh = false
    private(set) var actionErrors: [UUID: String] = [:]
    let userID: UUID
    private let repository: any ParkingSignalRepository
    private var observationTask: Task<Void, Never>?
    private var refreshVersion = 0

    init(repository: any ParkingSignalRepository, userID: UUID) {
        self.repository = repository
        self.userID = userID
    }

    var hasOpenSignalOwnedByCurrentUser: Bool {
        signals.contains {
            $0.createdBy == userID && !$0.status.isTerminal && $0.expiresAt > Date.now
        }
    }

    func refresh(now: Date = .now) async {
        refreshVersion += 1
        let version = refreshVersion
        isLoading = true
        do {
            let feed = try await repository.fetchFeed(now: now)
            guard version == refreshVersion else { return }
            signals = ParkingSignal.visible(feed.signals, at: now)
            let privateSignalIDs = Set(signals.lazy.filter {
                $0.createdBy == self.userID || $0.claimedBy == self.userID
            }.map(\.id))
            handoverDetails = feed.handoverDetails.filter { privateSignalIDs.contains($0.key) }
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

    func publish(
        zone: ParkingZone,
        minutes: Int,
        ownerVehicleID: UUID?,
        location: LocationReading,
        bayHint: String? = nil,
        now: Date = .now
    ) async -> Bool {
        guard !isPublishing else { return false }
        guard !hasOpenSignalOwnedByCurrentUser else {
            publishError = ParkingSignalRepositoryError.activeSignalExists.localizedDescription
            return false
        }
        guard let ownerVehicleID else {
            publishError = "Select the vehicle you’re leaving in."
            return false
        }
        guard zone.isActive, zone.isSupported, [0, 2, 5, 10].contains(minutes) else {
            publishError = "Choose a valid active parking zone and leaving time."
            return false
        }
        isPublishing = true
        publishError = nil
        publishRequiresLocationRefresh = false
        defer { isPublishing = false }
        do {
            let signal = ParkingSignal.leaving(userID: userID, parkingZone: zone, minutes: minutes, now: now)
            let published = try await repository.publish(PublishParkingSignalRequest(
                signal: signal,
                zoneID: zone.id,
                ownerVehicleID: ownerVehicleID,
                location: location
            ))
            guard published.createdBy == userID else { throw ParkingSignalRepositoryError.invalidSignalResponse }
            let trimmedHint = bayHint?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedHint, !trimmedHint.isEmpty {
                localBayHints[published.id] = String(trimmedHint.prefix(100))
            }
            apply(published, now: now)
            await refresh()
            return true
        } catch {
            publishError = "Could not publish signal: \(error.localizedDescription)"
            if let repositoryError = error as? ParkingSignalRepositoryError {
                publishRequiresLocationRefresh = [
                    .locationUnavailable, .locationInaccurate, .outsideParkingZone
                ].contains(repositoryError)
            }
            return false
        }
    }

    func claim(_ signal: ParkingSignal, claimantVehicleID: UUID?, now: Date = .now) async -> Bool {
        guard signal.allowedActions(for: userID).contains(.claim) else { return false }
        guard let claimantVehicleID else {
            actionErrors[signal.id] = "Select the vehicle you’re arriving in."
            return false
        }
        guard inFlightSignalIDs.insert(signal.id).inserted else { return false }
        actionErrors[signal.id] = nil
        defer { inFlightSignalIDs.remove(signal.id) }

        do {
            let claimed = try await repository.claim(signalID: signal.id, claimantVehicleID: claimantVehicleID)
            guard claimed.id == signal.id else {
                throw ParkingSignalRepositoryError.invalidSignalResponse
            }
            apply(claimed, now: now)
            await refresh(now: now)
            return true
        } catch {
            if let repositoryError = error as? ParkingSignalRepositoryError,
               repositoryError == .signalUnavailable {
                actionErrors[signal.id] = repositoryError.localizedDescription
            } else {
                actionErrors[signal.id] = "Could not claim signal: \(error.localizedDescription)"
            }
            await refresh()
            return false
        }
    }

    func perform(_ action: ParkingSignal.LifecycleAction, on signal: ParkingSignal, now: Date = .now) async -> Bool {
        guard action != .claim, action != .showPass,
              signal.allowedActions(for: userID).contains(action) else { return false }
        guard inFlightSignalIDs.insert(signal.id).inserted else { return false }
        actionErrors[signal.id] = nil
        defer { inFlightSignalIDs.remove(signal.id) }

        do {
            let updated: ParkingSignal
            switch action {
            case .arrive: updated = try await repository.markArrived(signalID: signal.id)
            case .release: updated = try await repository.releaseClaim(signalID: signal.id)
            case .cancel: updated = try await repository.cancel(signalID: signal.id)
            case .vacate: updated = try await repository.markVacated(signalID: signal.id)
            case .complete: updated = try await repository.complete(signalID: signal.id)
            case .unavailable: updated = try await repository.markUnavailable(signalID: signal.id)
            case .claim, .showPass: return false
            }
            guard updated.id == signal.id else {
                throw ParkingSignalRepositoryError.invalidSignalResponse
            }
            apply(updated, now: now)
            if updated.status.isTerminal {
                handoverDetails[signal.id] = nil
                localBayHints[signal.id] = nil
            }
            await refresh(now: now)
            return true
        } catch {
            actionErrors[signal.id] = "Could not complete action: \(error.localizedDescription)"
            await refresh()
            return false
        }
    }

    func isPerformingAction(on signalID: UUID) -> Bool {
        inFlightSignalIDs.contains(signalID)
    }

    func handover(for signal: ParkingSignal) -> HandoverDetails? {
        guard signal.createdBy == userID || signal.claimedBy == userID else { return nil }
        return handoverDetails[signal.id]
    }

    func localBayHint(for signalID: UUID) -> String? {
        localBayHints[signalID]
    }

    func clearActionError(for signalID: UUID) {
        actionErrors[signalID] = nil
    }

    func setActionError(_ message: String, for signalID: UUID) {
        actionErrors[signalID] = message
    }

    private func apply(_ signal: ParkingSignal, now: Date) {
        if let index = signals.firstIndex(where: { $0.id == signal.id }) {
            signals[index] = signal
        } else {
            signals.append(signal)
        }
        signals = ParkingSignal.visible(signals, at: now)
    }
}
