import Foundation
import Observation
import UIKit
import UserNotifications

protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

struct SystemNotificationCenterClient: NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }
}

@MainActor @Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private(set) var permissionState: NotificationPermissionState = .notRequested
    private(set) var registrationError: String?
    private(set) var pendingRoute: SpotSoonNotificationPayload?
    private let centerClient: any NotificationCenterClient
    private var repository: (any PushNotificationRepository)?
    private var token: String?
    private var syncedToken: String?
    private var syncTask: Task<Void, Never>?
    private var isSynchronizing = false
    private let deviceID: UUID

    init(
        centerClient: any NotificationCenterClient = SystemNotificationCenterClient(),
        deviceID: UUID? = nil
    ) {
        self.centerClient = centerClient
        let defaultsKey = "SpotSoon.pushDeviceID"
        if let deviceID { self.deviceID = deviceID }
        else if let stored = UserDefaults.standard.string(forKey: defaultsKey), let id = UUID(uuidString: stored) {
            self.deviceID = id
        } else {
            let id = UUID()
            UserDefaults.standard.set(id.uuidString, forKey: defaultsKey)
            self.deviceID = id
        }
        super.init()
    }

    func configure(repository: any PushNotificationRepository) async {
        self.repository = repository
        UNUserNotificationCenter.current().delegate = self
        await refreshAuthorization()
        await synchronizeTokenIfNeeded()
    }

    func refreshAuthorization() async {
        permissionState = NotificationPermissionState(await centerClient.authorizationStatus())
        if permissionState.canRegister {
            UIApplication.shared.registerForRemoteNotifications()
        } else if permissionState == .denied, let repository {
            try? await repository.deactivate(deviceID: deviceID, environment: .current)
            syncedToken = nil
        }
    }

    func requestContextualPermissionIfNeeded() async {
        await refreshAuthorization()
        guard permissionState == .notRequested else { return }
        do {
            _ = try await centerClient.requestAuthorization()
            await refreshAuthorization()
        } catch {
            registrationError = "Notification permission could not be requested: \(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func receivedDeviceToken(_ data: Data) {
        token = data.hexadecimalString
        registrationError = nil
        scheduleTokenSynchronization()
    }

    func remoteRegistrationFailed(_ error: Error) {
        registrationError = "Remote notification registration failed: \(error.localizedDescription)"
    }

    func consumePendingRoute() -> SpotSoonNotificationPayload? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    func accept(_ payload: SpotSoonNotificationPayload) { pendingRoute = payload }

    func retryTokenSynchronization() async { await synchronizeTokenIfNeeded() }

    private func scheduleTokenSynchronization() {
        syncTask?.cancel()
        syncTask = Task { await synchronizeTokenIfNeeded() }
    }

    private func synchronizeTokenIfNeeded() async {
        guard !isSynchronizing, let repository, let token, token != syncedToken else { return }
        isSynchronizing = true
        do {
            try await repository.register(token: token, deviceID: deviceID, environment: .current)
            syncedToken = token
            registrationError = nil
        } catch {
            registrationError = "Notification registration will retry: \(error.localizedDescription)"
        }
        isSynchronizing = false
        if self.token != token { scheduleTokenSynchronization() }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let payload = SpotSoonNotificationPayload(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { self.accept(payload) }
    }
}
