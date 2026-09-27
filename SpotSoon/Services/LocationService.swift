import CoreLocation
import Foundation
import Observation
import UIKit

nonisolated enum LocationAuthorizationState: Equatable, Sendable {
    case notRequested, denied, restricted, authorized

    var title: String {
        switch self {
        case .notRequested: "Not requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .authorized: "Allowed While Using App"
        }
    }
}

nonisolated enum LocationServiceError: LocalizedError, Equatable, Sendable {
    case permissionDenied, permissionRestricted, unavailable, invalidReading, staleReading, requestInProgress

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Location access is denied."
        case .permissionRestricted: "Location access is restricted on this device."
        case .unavailable: "A location reading is currently unavailable."
        case .invalidReading: "The device returned an invalid location reading."
        case .staleReading: "The device location is out of date."
        case .requestInProgress: "A location request is already running."
        }
    }
}

@MainActor
protocol LocationProviding: AnyObject {
    var authorizationStatus: LocationAuthorizationState { get }
    func requestWhenInUseAuthorization() async -> LocationAuthorizationState
    func requestLocation() async throws -> LocationReading
}

@MainActor
protocol ApproachLocationProviding: AnyObject {
    var approachAuthorizationStatus: LocationAuthorizationState { get }
    func requestApproachAuthorization() async -> LocationAuthorizationState
    func requestApproachLocation() async throws -> LocationReading
    func openApproachSettings()
}

@MainActor
final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<LocationAuthorizationState, Never>?
    private var locationContinuation: CheckedContinuation<LocationReading, any Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var authorizationStatus: LocationAuthorizationState {
        Self.authorizationState(for: manager.authorizationStatus)
    }

    func requestWhenInUseAuthorization() async -> LocationAuthorizationState {
        guard authorizationStatus == .notRequested else { return authorizationStatus }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestLocation() async throws -> LocationReading {
        switch authorizationStatus {
        case .denied: throw LocationServiceError.permissionDenied
        case .restricted: throw LocationServiceError.permissionRestricted
        case .notRequested: throw LocationServiceError.unavailable
        case .authorized: break
        }
        guard locationContinuation == nil else { throw LocationServiceError.requestInProgress }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let state = authorizationStatus
        guard state != .notRequested else { return }
        authorizationContinuation?.resume(returning: state)
        authorizationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        guard let location = locations.last else {
            continuation.resume(throwing: LocationServiceError.unavailable)
            return
        }
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0 else {
            continuation.resume(throwing: LocationServiceError.invalidReading)
            return
        }
        guard abs(Date.now.timeIntervalSince(location.timestamp)) <= 15 else {
            continuation.resume(throwing: LocationServiceError.staleReading)
            return
        }
        continuation.resume(returning: LocationReading(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        locationContinuation?.resume(throwing: LocationServiceError.unavailable)
        locationContinuation = nil
    }

    private static func authorizationState(for status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
        case .notDetermined: .notRequested
        case .denied: .denied
        case .restricted: .restricted
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .restricted
        }
    }
}

@MainActor @Observable
final class LocationStore {
    nonisolated enum VerificationState: Equatable {
        case notRequested
        case permissionDenied
        case restricted
        case locating
        case inaccurate(accuracy: Double)
        case outsideZone(distance: Double, accuracy: Double)
        case verified(ZoneVerificationResult)
        case unavailable
        case error(String)

        var isVerified: Bool {
            if case .verified = self { return true }
            return false
        }
    }

    private(set) var authorizationState: LocationAuthorizationState
    private(set) var verificationState: VerificationState
    private(set) var latestReading: LocationReading?
    private(set) var suggestedZoneID: String?
    private(set) var verificationZoneID: String?

    private let provider: any LocationProviding
    private let verifier: ZoneVerifier

    init(provider: any LocationProviding, verifier: ZoneVerifier = ZoneVerifier()) {
        self.provider = provider
        self.verifier = verifier
        authorizationState = provider.authorizationStatus
        switch provider.authorizationStatus {
        case .denied: verificationState = .permissionDenied
        case .restricted: verificationState = .restricted
        case .notRequested, .authorized: verificationState = .notRequested
        }
    }

    func refreshAuthorizationState() {
        authorizationState = provider.authorizationStatus
        switch authorizationState {
        case .denied: verificationState = .permissionDenied
        case .restricted: verificationState = .restricted
        case .notRequested: verificationState = .notRequested
        case .authorized: break
        }
    }

    func requestPermission() async {
        authorizationState = await provider.requestWhenInUseAuthorization()
        refreshAuthorizationState()
    }

    func requestPermissionAndVerify(zone: ParkingZone) async {
        authorizationState = await provider.requestWhenInUseAuthorization()
        await verify(zone: zone)
    }

    func requestPermissionAndVerify(zone: ParkingZone, availableZones: [ParkingZone]) async {
        authorizationState = await provider.requestWhenInUseAuthorization()
        await verify(zone: zone, availableZones: availableZones)
    }

    func verify(zone: ParkingZone, availableZones: [ParkingZone] = []) async {
        refreshAuthorizationState()
        suggestedZoneID = nil
        verificationZoneID = zone.id
        switch authorizationState {
        case .notRequested:
            verificationState = .notRequested
            return
        case .denied:
            verificationState = .permissionDenied
            return
        case .restricted:
            verificationState = .restricted
            return
        case .authorized:
            break
        }

        verificationState = .locating
        do {
            let reading = try await provider.requestLocation()
            latestReading = reading
            let result = verifier.verify(zone: zone, reading: reading)
            if result.accepted {
                verificationState = .verified(result)
            } else {
                switch result.failure {
                case .inaccurateLocation:
                    verificationState = .inaccurate(accuracy: result.horizontalAccuracy)
                case .outsideZone:
                    verificationState = .outsideZone(
                        distance: result.distanceMeters ?? 0,
                        accuracy: result.horizontalAccuracy
                    )
                    suggestedZoneID = verifier.suggestedAlternative(
                        to: zone,
                        among: availableZones,
                        reading: reading
                    )?.id
                case .invalidLocation, .staleLocation:
                    verificationState = .unavailable
                case .inactiveZone, .unknownZone:
                    verificationState = .error(result.failure?.localizedDescription ?? "Zone unavailable.")
                case nil:
                    verificationState = .error("Location verification failed.")
                }
            }
        } catch let error as LocationServiceError {
            switch error {
            case .permissionDenied: verificationState = .permissionDenied
            case .permissionRestricted: verificationState = .restricted
            case .unavailable, .invalidReading, .staleReading: verificationState = .unavailable
            case .requestInProgress: verificationState = .error(error.localizedDescription)
            }
        } catch {
            verificationState = .error(error.localizedDescription)
        }
    }

    func invalidateVerification() {
        latestReading = nil
        suggestedZoneID = nil
        verificationZoneID = nil
        switch authorizationState {
        case .denied: verificationState = .permissionDenied
        case .restricted: verificationState = .restricted
        case .notRequested, .authorized: verificationState = .notRequested
        }
    }

    func switchAndVerify(to zone: ParkingZone, availableZones: [ParkingZone]) async {
        invalidateVerification()
        await verify(zone: zone, availableZones: availableZones)
    }

    func isVerified(for zoneID: String) -> Bool {
        verificationZoneID == zoneID && verificationState.isVerified
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension LocationStore: ApproachLocationProviding {
    var approachAuthorizationStatus: LocationAuthorizationState { provider.authorizationStatus }

    func requestApproachAuthorization() async -> LocationAuthorizationState {
        let result = await provider.requestWhenInUseAuthorization()
        refreshAuthorizationState()
        return result
    }

    func requestApproachLocation() async throws -> LocationReading {
        try await provider.requestLocation()
    }

    func openApproachSettings() { openSettings() }
}
