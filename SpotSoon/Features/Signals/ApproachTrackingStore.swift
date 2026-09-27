import Foundation
import Observation

nonisolated protocol ApproachClock: Sendable {
    var now: Date { get }
    func sleep(seconds: TimeInterval) async throws
}

nonisolated struct SystemApproachClock: ApproachClock {
    var now: Date { .now }
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

@MainActor @Observable
final class ApproachTrackingStore {
    private(set) var location: ApproachLocation?
    private(set) var isSharing = false
    private(set) var isWorking = false
    private(set) var isWaitingForReading = false
    private(set) var errorMessage: String?
    private(set) var authorizationState: LocationAuthorizationState

    let signalID: UUID
    let isClaimant: Bool
    private let repository: any ApproachTrackingRepository
    private let provider: any ApproachLocationProviding
    private let clock: any ApproachClock
    private let distanceCalculator: any ApproachDistanceCalculating
    private var loopTask: Task<Void, Never>?
    private var lastUploaded: ApproachPoint?
    private var restored = false

    init(
        repository: any ApproachTrackingRepository,
        provider: any ApproachLocationProviding,
        signalID: UUID,
        isClaimant: Bool,
        clock: any ApproachClock = SystemApproachClock(),
        distanceCalculator: any ApproachDistanceCalculating = CoreLocationApproachDistanceCalculator()
    ) {
        self.repository = repository
        self.provider = provider
        self.signalID = signalID
        self.isClaimant = isClaimant
        self.clock = clock
        self.distanceCalculator = distanceCalculator
        authorizationState = provider.approachAuthorizationStatus
    }

    var distance: Double? {
        guard let location, let claimant = location.claimant else { return nil }
        return distanceCalculator.distance(from: location.owner, to: claimant)
    }

    var approachBand: ApproachBand? { distance.map(ApproachBand.init(distance:)) }
    var freshness: ApproachFreshness { .evaluate(location: location, now: clock.now) }

    func start() async {
        guard loopTask == nil else { return }
        if isClaimant, !restored {
            restored = true
            // Sharing is deliberately opt-in after every launch/presentation.
            _ = try? await setSharingOnServer(false)
            isSharing = false
        }
        await refresh()
        loopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.isSharing { await self.captureAndUpload() }
                await self.refresh()
                do { try await self.clock.sleep(seconds: 5) }
                catch { break }
            }
        }
    }

    func refresh() async {
        do {
            location = try await repository.fetch(signalID: signalID)
            if isClaimant, !isSharing, location?.claimantSharingEnabled == true {
                // A terminated process may have left the server flag enabled. A
                // restored screen always returns it to the required opt-in state.
                location = try await setSharingOnServer(false)
            }
            if !isSharing { lastUploaded = location?.claimant }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Live approach location is temporarily unavailable."
        }
    }

    func enableSharing() async {
        guard isClaimant, !isWorking, !isSharing else { return }
        isWorking = true
        defer { isWorking = false }
        authorizationState = provider.approachAuthorizationStatus
        if authorizationState == .notRequested {
            authorizationState = await provider.requestApproachAuthorization()
        }
        guard authorizationState == .authorized else { return }
        do {
            location = try await setSharingOnServer(true)
            isSharing = true
            isWaitingForReading = true
            errorMessage = nil
            await captureAndUpload()
        } catch {
            isSharing = false
            errorMessage = error.localizedDescription
        }
    }

    func pauseSharing() async {
        guard isClaimant else { return }
        isSharing = false
        isWaitingForReading = false
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            location = try await setSharingOnServer(false)
            errorMessage = nil
        } catch {
            errorMessage = "Could not pause live approach sharing."
        }
    }

    func stop() async {
        loopTask?.cancel()
        loopTask = nil
        if isSharing { await pauseSharing() }
    }

    func captureAndUpload() async {
        guard isClaimant, isSharing else { return }
        do {
            let reading = try await provider.requestApproachLocation()
            guard isSharing, !Task.isCancelled else { return }
            guard ApproachReadingPolicy.shouldUpload(
                reading, after: lastUploaded, now: clock.now,
                distanceCalculator: distanceCalculator
            ) else {
                if !ApproachReadingPolicy.accepts(reading, now: clock.now) {
                    isWaitingForReading = true
                }
                return
            }
            let updated = try await repository.update(signalID: signalID, reading: reading)
            location = updated
            lastUploaded = updated.claimant
            isWaitingForReading = false
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as LocationServiceError {
            isWaitingForReading = true
            if [.permissionDenied, .permissionRestricted].contains(error) {
                isSharing = false
            }
            errorMessage = error.localizedDescription
        } catch {
            // Stop immediately on a rejected server update. This includes an
            // ended authenticated session and prevents unattended retries.
            isSharing = false
            isWaitingForReading = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not update live approach location."
        }
    }

    func formattedDistance() -> String? {
        guard let distance else { return nil }
        let rounded = distance < 100 ? (distance / 5).rounded() * 5 : (distance / 10).rounded() * 10
        return "Approximately \(Int(rounded)) m away"
    }

    func openSettings() { provider.openApproachSettings() }

    private func setSharingOnServer(_ enabled: Bool) async throws -> ApproachLocation {
        try await repository.setSharing(signalID: signalID, enabled: enabled)
    }
}
