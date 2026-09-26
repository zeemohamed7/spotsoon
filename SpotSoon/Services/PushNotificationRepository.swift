import Foundation
import Supabase

@MainActor
protocol PushNotificationRepository {
    func register(token: String, deviceID: UUID, environment: PushEnvironment) async throws
    func deactivate(deviceID: UUID, environment: PushEnvironment) async throws
}

enum PushNotificationRepositoryError: LocalizedError, Equatable {
    case registrationRejected

    var errorDescription: String? { "SpotSoon could not register this device for notifications." }
}

@MainActor
final class SupabasePushNotificationRepository: PushNotificationRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func register(token: String, deviceID: UUID, environment: PushEnvironment) async throws {
        do {
            try await client.rpc("register_push_device", params: RegisterPushDeviceParameters(
                token: token, deviceID: deviceID, environment: environment.rawValue
            )).execute()
        } catch let error as PostgrestError {
            let diagnostic = [error.code, error.message, error.details, error.hint]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            if diagnostic.contains("push_device_registration_rejected") {
                throw PushNotificationRepositoryError.registrationRejected
            }
            throw error
        }
    }

    func deactivate(deviceID: UUID, environment: PushEnvironment) async throws {
        try await client.rpc("deactivate_push_device", params: DeactivatePushDeviceParameters(
            deviceID: deviceID, environment: environment.rawValue
        )).execute()
    }
}

private struct RegisterPushDeviceParameters: Encodable {
    let token: String
    let deviceID: UUID
    let environment: String
    enum CodingKeys: String, CodingKey {
        case token = "p_token"
        case deviceID = "p_device_id"
        case environment = "p_environment"
    }
}

private struct DeactivatePushDeviceParameters: Encodable {
    let deviceID: UUID
    let environment: String
    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case environment = "p_environment"
    }
}
