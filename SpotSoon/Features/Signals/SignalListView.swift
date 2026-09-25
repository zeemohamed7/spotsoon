import SwiftUI

struct SignalListView: View {
    let store: SignalStore
    let vehicleStore: VehicleStore
    let zoneStore: ParkingZoneStore
    let locationStore: LocationStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingCreate = false
    @State private var retryID = UUID()
    @State private var signalToClaim: ParkingSignal?
    @State private var handoverPass: HandoverDetails?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZoneMapView(zoneStore: zoneStore, locationStore: locationStore)
                    .frame(height: 300)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let visible = ParkingSignal.visible(store.signals, at: context.date)
                        .filter { $0.campus == (zoneStore.selectedZone?.campus ?? .campusA) }
                    List {
                        Button("Create leaving signal", systemImage: "plus") {
                            store.publishError = nil
                            showingCreate = true
                        }
                        if let zone = zoneStore.selectedZone {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(zone.name).font(.headline)
                                Text(zone.landmark).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if zoneStore.isLoading { ProgressView("Loading parking area…") }
                        if let error = zoneStore.errorMessage { Text(error).foregroundStyle(.red) }
                        if let error = store.connectionError {
                            Text(error).foregroundStyle(.red)
                            Button("Retry live updates") { retryID = UUID() }
                        }
                        if let error = store.listError { Text(error).foregroundStyle(.red) }
                        if store.isLoading { ProgressView("Loading signals…") }
                        if visible.isEmpty && !store.isLoading && store.listError == nil {
                            Text("No active signals. Publish one when you’re about to leave.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(visible) { signal in
                            SignalRowView(
                                store: store,
                                signal: signal,
                                now: context.date,
                                claim: {
                                    store.clearActionError(for: signal.id)
                                    signalToClaim = signal
                                },
                                showPass: { handoverPass = $0 }
                            )
                        }
                    }
                    .refreshable {
                        await zoneStore.load()
                        await store.refresh()
                    }
                }
            }
            .navigationTitle("SpotSoon")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(vehicleStore: vehicleStore, locationStore: locationStore)
                    } label: {
                        Label("Settings", systemImage: "person.crop.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                }
            }
            .sheet(isPresented: $showingCreate) {
                if let zone = zoneStore.selectedZone {
                    CreateSignalView(
                        store: store,
                        vehicleStore: vehicleStore,
                        locationStore: locationStore,
                        zone: zone
                    )
                } else {
                    ContentUnavailableView(
                        "Parking area unavailable",
                        systemImage: "mappin.slash",
                        description: Text("Refresh after the parking-zone migration is installed.")
                    )
                }
            }
            .sheet(item: $signalToClaim) { signal in
                ClaimSignalView(store: store, vehicleStore: vehicleStore, signal: signal)
            }
            .fullScreenCover(item: $handoverPass) { HandoverPassView(details: $0) }
        }
        .task(id: "\(scenePhase == .active)-\(retryID)") {
            if scenePhase == .active { await store.run() }
        }
        .task { if zoneStore.zones.isEmpty { await zoneStore.load() } }
    }
}
