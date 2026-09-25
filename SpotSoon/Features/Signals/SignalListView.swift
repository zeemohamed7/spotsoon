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
    @State private var pendingHandoverPass: HandoverDetails?
    @State private var completedSignal: ParkingSignal?

    private var signalCounts: [String: Int] {
        let visible = ParkingSignal.visible(store.signals, at: .now)
        return Dictionary(uniqueKeysWithValues: zoneStore.zones.map { zone in
            (zone.id, visible.lazy.filter { $0.belongs(to: zone) }.count)
        })
    }

    private var waitingSignal: ParkingSignal? {
        ParkingSignal.visible(store.signals, at: .now).first {
            $0.createdBy == store.userID && $0.status == .active
        }
    }

    private var liveHandoverSignal: ParkingSignal? {
        ParkingSignal.visible(store.signals, at: .now).first {
            ($0.createdBy == store.userID || $0.claimedBy == store.userID)
                && [.claimed, .arrived, .vacated].contains($0.status)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let completedSignal {
                    HandoverCompleteView(signal: completedSignal) {
                        self.completedSignal = nil
                    }
                } else if let waitingSignal {
                    OwnerWaitingView(
                        store: store,
                        signal: waitingSignal,
                        vehicleStore: vehicleStore,
                        locationStore: locationStore
                    )
                } else if let liveHandoverSignal {
                    LiveHandoverView(
                        store: store,
                        signal: liveHandoverSignal,
                        showPass: { handoverPass = $0 },
                        completed: { completedSignal = $0 }
                    )
                } else {
                    ZStack(alignment: .top) {
                        ZoneMapView(
                            zoneStore: zoneStore,
                            locationStore: locationStore,
                            signalCounts: signalCounts
                        )
                        .ignoresSafeArea(edges: .top)

                        mapHeader
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            signalPanel(at: context.date)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCreate) {
                CreateSignalView(
                    store: store,
                    vehicleStore: vehicleStore,
                    locationStore: locationStore,
                    zoneStore: zoneStore,
                    initialZone: zoneStore.selectedZone ?? .campusAStudent
                )
                .presentationDetents([.fraction(0.86)])
                .presentationDragIndicator(.hidden)
                .presentationContentInteraction(.scrolls)
                .presentationBackground(.white)
                .presentationCornerRadius(30)
            }
            .sheet(item: $signalToClaim, onDismiss: showPendingHandoverPass) { signal in
                ClaimSignalView(
                    store: store,
                    vehicleStore: vehicleStore,
                    signal: signal,
                    onClaimed: { pendingHandoverPass = $0 }
                )
                .presentationDetents([.fraction(0.74)])
                .presentationDragIndicator(.hidden)
                .presentationContentInteraction(.scrolls)
                .presentationBackground(.white)
                .presentationCornerRadius(30)
            }
            .fullScreenCover(item: $handoverPass) { HandoverPassView(details: $0) }
        }
        .task(id: "\(scenePhase == .active)-\(retryID)") {
            if scenePhase == .active { await store.run() }
        }
        .task { if zoneStore.zones.isEmpty { await zoneStore.load() } }
    }

    private var mapHeader: some View {
        VStack(spacing: 10) {
            HStack {
                SpotSoonLogo(compact: true)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task {
                        await zoneStore.load()
                        await store.refresh()
                    }
                }
                .labelStyle(.iconOnly)
                .frame(width: 42, height: 42)
                .background(.regularMaterial, in: Circle())

                NavigationLink {
                    SettingsView(vehicleStore: vehicleStore, locationStore: locationStore)
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title3.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Profile and settings")
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

            if let zone = zoneStore.selectedZone {
                HStack(spacing: 7) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text(zone.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("Live")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func signalPanel(at now: Date) -> some View {
        let visible = ParkingSignal.visible(store.signals, in: zoneStore.selectedZone, at: now)
        VStack(spacing: 14) {
            Capsule()
                .fill(.secondary.opacity(0.25))
                .frame(width: 42, height: 5)

            HStack(alignment: .firstTextBaseline) {
                Text(visible.isEmpty ? "Nearby parking" : "Signals")
                    .font(.title3.bold())
                    .foregroundStyle(Color.spotInk)
                if !visible.isEmpty {
                    Text("\(visible.count) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
            }

            statusMessages

            if visible.isEmpty && !store.isLoading && store.listError == nil {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.spotPurple)
                        .frame(width: 48, height: 48)
                        .background(Color.spotLavender, in: Circle())
                    Text("No Active Signals Nearby")
                        .font(.headline)
                    Text("Be the first to share when you’re leaving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else if !visible.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visible) { signal in
                            SignalRowView(
                                store: store,
                                signal: signal,
                                now: now,
                                claim: {
                                    store.clearActionError(for: signal.id)
                                    signalToClaim = signal
                                },
                                showPass: { handoverPass = $0 }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: visible.contains(where: {
                    $0.status == .active && $0.createdBy == store.userID
                }) ? 460 : 280)
            }

            Button {
                store.publishError = nil
                showingCreate = true
            } label: {
                Label(
                    store.hasOpenSignalOwnedByCurrentUser ? "Signal Already Shared" : "Share Your Spot",
                    systemImage: "dot.radiowaves.left.and.right"
                )
            }
            .buttonStyle(SpotSoonPrimaryButtonStyle())
            .disabled(store.hasOpenSignalOwnedByCurrentUser)

            if store.hasOpenSignalOwnedByCurrentUser {
                Text("Finish or cancel your current signal before sharing another.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThickMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.12), radius: 18, y: -4)
    }

    @ViewBuilder
    private var statusMessages: some View {
        if zoneStore.isLoading { ProgressView("Loading parking areas…") }
        if store.isLoading { ProgressView("Loading live signals…") }
        if let error = zoneStore.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red)
        }
        if let error = store.listError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
        if let error = store.connectionError {
            VStack(spacing: 6) {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("Retry live updates") { retryID = UUID() }
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func selectZone(_ id: String) {
        guard id != zoneStore.selectedZoneID, zoneStore.selectZone(id: id) else { return }
        locationStore.invalidateVerification()
    }

    private func showPendingHandoverPass() {
        guard let pendingHandoverPass else { return }
        self.pendingHandoverPass = nil
        handoverPass = pendingHandoverPass
    }
}
