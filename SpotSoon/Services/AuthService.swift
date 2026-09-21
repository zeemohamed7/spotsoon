import Foundation
import Supabase

@MainActor
final class AuthService {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func restoreOrSignIn() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch AuthError.sessionMissing {
            return try await client.auth.signInAnonymously().user.id
        }
        // Network/refresh failures must stay visible, not create another identity.
    }
}
