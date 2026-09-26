import SwiftUI

struct ContentView: View {
    @State private var store: SignalStore?
    @State private var vehicleStore: VehicleStore?
    @State private var zoneStore: ParkingZoneStore?
    @State private var locationStore: LocationStore?
    @State private var error: String?
    @State private var loading = false
    @AppStorage("hasCompletedPhaseOneOnboarding") private var hasCompletedOnboarding = false
    @State private var isPreviewingOnboarding = ProcessInfo.processInfo.arguments.contains("--show-onboarding")

    private var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding || isPreviewingOnboarding
    }

    var body: some View {
        Group {
            if let store, let vehicleStore, let zoneStore, let locationStore {
                if shouldShowOnboarding {
                    OnboardingFlowView(locationStore: locationStore) {
                        hasCompletedOnboarding = true
                        isPreviewingOnboarding = false
                    }
                } else {
                    SignalListView(
                        store: store,
                        vehicleStore: vehicleStore,
                        zoneStore: zoneStore,
                        locationStore: locationStore
                    )
                }
            } else {
                NavigationStack {
                    ZStack {
                        Color.spotBackground.ignoresSafeArea()

                        VStack(spacing: 22) {
                            SpotSoonLogo()
                            Text("SpotSoon")
                                .font(.largeTitle.bold())
                                .foregroundStyle(Color.spotTextPrimary)
                            if loading {
                                ProgressView("Preparing your private session…")
                                    .foregroundStyle(Color.spotTextSecondary)
                                    .tint(Color.spotAccent)
                            }
                            if let error {
                                Text(error).foregroundStyle(Color.spotError)
                                Button("Retry") { Task { await start() } }.disabled(loading)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .tint(Color.spotAccent)
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
