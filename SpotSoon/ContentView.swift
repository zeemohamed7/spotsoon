import SwiftUI

struct ContentView: View {
    @State private var store: SignalStore?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        Group {
            if let store {
                SignalListView(store: store)
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if loading { ProgressView("Starting anonymous session…") }
                        if let error {
                            Text(error).foregroundStyle(.red)
                            Button("Retry") { Task { await start() } }.disabled(loading)
                        }
                    }.padding().navigationTitle("SpotSoon")
                }
            }
        }
        .task { if store == nil { await start() } }
    }

    @MainActor private func start() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let client = try SupabaseClientProvider.makeClient()
            let userID = try await AuthService(client: client).restoreOrSignIn()
            store = SignalStore(repository: SupabaseParkingSignalRepository(client: client), userID: userID)
        } catch {
            self.error = "Could not start SpotSoon: \(error.localizedDescription)"
        }
    }
}
