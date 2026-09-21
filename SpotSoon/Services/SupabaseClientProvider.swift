import Foundation
import Supabase

enum SupabaseClientProvider {
    static func makeClient(bundle: Bundle = .main) throws -> SupabaseClient {
        guard let file = bundle.url(forResource: "Supabase.local", withExtension: "plist"),
              let data = try? Data(contentsOf: file),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data),
              let rawURL = values["SUPABASE_URL"],
              let url = URL(string: rawURL), url.scheme == "https", url.host != nil,
              !rawURL.contains("YOUR_"),
              let key = values["SUPABASE_PUBLISHABLE_KEY"], key.hasPrefix("sb_publishable_"),
              key.count > "sb_publishable_".count else {
            throw ConfigurationError.missing
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    enum ConfigurationError: LocalizedError {
        case missing
        var errorDescription: String? {
            "Development configuration missing or invalid. Copy Configuration/Supabase.example.plist to SpotSoon/Supabase.local.plist, set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (sb_publishable_…), then rebuild."
        }
    }
}
