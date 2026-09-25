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

    private var signalCounts: [String: Int] {
        let visible = ParkingSignal.visible(store.signals, at: .now)
        return Dictionary(uniqueKeysWithValues: zoneStore.zones.map { zone in
            (zone.id, visible.lazy.filter { $0.belongs(to: zone) }.count)
        })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZoneMapView(
                    zoneStore: zoneStore,
                    locationStore: locationStore,
                    signalCounts: signalCounts
                )
                    .frame(height: 300)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let visible = ParkingSignal.visible(
                        store.signals,
                        in: zoneStore.selectedZone,
                        at: context.date
                    )
                    List {
                        Button("Create leaving signal", systemImage: "plus") {
                            store.publishError = nil
                            showingCreate = true
                        }
                        .disabled(store.hasOpenSignalOwnedByCurrentUser)
                        if store.hasOpenSignalOwnedByCurrentUser {
                            Text("You already have an open parking signal. Finish or cancel it before creating another.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let zone = zoneStore.selectedZone {
                            Picker("Parking area", selection: Binding(
                                get: { zone.id },
                                set: { selectZone($0) }
                            )) {
                                ForEach(zoneStore.zones) { option in
                                    Text(option.selectionLabel).tag(option.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(zone.name).font(.headline)
                                if let context = zone.alternativeContext {
                                    Text(context).font(.caption).foregroundStyle(.secondary)
                                }
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
                        zoneStore: zoneStore,
                        initialZone: zone
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

    private func selectZone(_ id: String) {
        guard id != zoneStore.selectedZoneID, zoneStore.selectZone(id: id) else { return }
        locationStore.invalidateVerification()
    }
}
