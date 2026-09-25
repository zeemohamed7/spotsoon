import SwiftUI

struct ContentView: View {
    @State private var store: SignalStore?
    @State private var vehicleStore: VehicleStore?
    @State private var zoneStore: ParkingZoneStore?
    @State private var locationStore: LocationStore?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        Group {
            if let store, let vehicleStore, let zoneStore, let locationStore {
                SignalListView(
                    store: store,
                    vehicleStore: vehicleStore,
                    zoneStore: zoneStore,
                    locationStore: locationStore
                )
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
            vehicleStore = VehicleStore(repository: SupabaseVehicleRepository(client: client), userID: userID)
            zoneStore = ParkingZoneStore(repository: SupabaseParkingZoneRepository(client: client))
            locationStore = LocationStore(provider: CoreLocationService())
        } catch {
            self.error = "Could not start SpotSoon: \(error.localizedDescription)"
        }
    }
}
