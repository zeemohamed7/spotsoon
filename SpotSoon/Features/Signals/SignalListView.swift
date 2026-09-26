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
    @State private var handoverNavigation = HandoverNavigationState()
    @State private var completedSignal: ParkingSignal?
    @State private var selectedRootTab: SpotSoonRootTab = .map

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

    private var ownerHandoverSignal: ParkingSignal? {
        ParkingSignal.visible(store.signals, at: .now).first {
            $0.createdBy == store.userID
                && [.claimed, .arrived, .vacated].contains($0.status)
        }
    }

    private var claimantHandoverSignal: ParkingSignal? {
        HandoverNavigationState.restorableClaimantSignal(
            in: store.signals, userID: store.userID, now: .now
        )
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
                } else if let ownerHandoverSignal {
                    LiveHandoverView(
                        store: store,
                        signal: ownerHandoverSignal,
                        close: nil,
                        completed: { completedSignal = $0 }
                    )
                } else if selectedRootTab == .garage {
                    GarageView(store: vehicleStore)
                        .toolbar(.visible, for: .navigationBar)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            bottomNavigation
                                .padding(.horizontal, 18)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                                .background(Color.spotGroupedBackground.opacity(0.96))
                        }
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
                        VStack(spacing: 18) {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                signalPanel(at: context.date)
                                    .padding(.horizontal, 16)
                            }
                            bottomNavigation
                        }
                        .padding(.bottom, 10)
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
                .presentationDetents([.fraction(0.86), .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.resizes)
                .presentationBackground(Color.spotBackground)
            }
            .sheet(item: $signalToClaim, onDismiss: presentClaimedHandover) { signal in
                ClaimSignalView(
                    store: store,
                    vehicleStore: vehicleStore,
                    signal: signal,
                    onClaimed: { handoverNavigation.claimSucceeded(signalID: signal.id) }
                )
                .presentationDetents([.fraction(0.74)])
                .presentationDragIndicator(.hidden)
                .presentationContentInteraction(.scrolls)
                .presentationBackground(Color.spotBackground)
                .presentationCornerRadius(30)
            }
            .fullScreenCover(item: Binding(
                get: { handoverNavigation.liveRoute },
                set: { route in
                    if route == nil { handoverNavigation.closeLiveHandover() }
                    else { handoverNavigation.liveRoute = route }
                }
            )) { route in
                LiveHandoverDestination(
                    store: store,
                    signalID: route.signalID,
                    closed: { handoverNavigation.closeLiveHandover() },
                    completed: { signal in
                        handoverNavigation.closeLiveHandover()
                        completedSignal = signal
                    }
                )
            }
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
                    Circle().fill(Color.spotSuccess).frame(width: 7, height: 7)
                    Text(zone.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("Live")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.spotSuccess)
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
        let compactSignals = visible.filter { $0.id != claimantHandoverSignal?.id }
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.spotTextMuted.opacity(0.32))
                .frame(width: 40, height: 5)

            HStack(alignment: .firstTextBaseline) {
                Text(visible.isEmpty ? "Nearby parking" : "Signals")
                    .font(.title3.bold())
                    .foregroundStyle(Color.spotTextPrimary)
                if !visible.isEmpty {
                    Text("\(visible.count) active")
                        .font(.caption)
                        .foregroundStyle(Color.spotTextSecondary)
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

            if let claimantHandoverSignal {
                claimantResumeCard(claimantHandoverSignal)
            }

            if compactSignals.isEmpty && claimantHandoverSignal == nil
                && !store.isLoading && store.listError == nil {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.spotAccent)
                        .frame(width: 48, height: 48)
                        .background(Color.spotAccentSoft, in: RoundedRectangle(cornerRadius: 15))
                    Text("No Active Signals Nearby")
                        .font(.headline)
                    Text("Be the first to share when you’re leaving.")
                        .font(.caption)
                        .foregroundStyle(Color.spotTextSecondary)
                }
                .padding(.vertical, 4)
            } else if !compactSignals.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(compactSignals) { signal in
                            SignalRowView(
                                store: store,
                                signal: signal,
                                now: now,
                                claim: {
                                    store.clearActionError(for: signal.id)
                                    signalToClaim = signal
                                },
                                resume: { handoverNavigation.resume(signalID: signal.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: visible.contains(where: {
                    $0.status == .active && $0.createdBy == store.userID
                }) ? 460 : 280)
            }

        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color.spotSurface.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.spotBorder, lineWidth: 1)
        }
        .shadow(color: Color.spotOverlay.opacity(0.2), radius: 22, y: 8)
    }

    @ViewBuilder
    private var statusMessages: some View {
        if zoneStore.isLoading { ProgressView("Loading parking areas…") }
        if store.isLoading { ProgressView("Loading live signals…") }
        if let error = zoneStore.errorMessage {
            Text(error).font(.caption).foregroundStyle(Color.spotError)
        }
        if let error = store.listError {
            Text(error).font(.caption).foregroundStyle(Color.spotError)
        }
        if let error = store.connectionError {
            VStack(spacing: 6) {
                Text(error).font(.caption).foregroundStyle(Color.spotError)
                Button("Retry live updates") { retryID = UUID() }
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func selectZone(_ id: String) {
        guard id != zoneStore.selectedZoneID, zoneStore.selectZone(id: id) else { return }
        locationStore.invalidateVerification()
    }

    private func openPublishSheet() {
        guard !store.hasOpenSignalOwnedByCurrentUser, claimantHandoverSignal == nil else { return }
        store.publishError = nil
        showingCreate = true
    }

    private var bottomNavigation: some View {
        SpotSoonBottomNavigationBar(
            selection: selectedRootTab,
            canShare: !store.hasOpenSignalOwnedByCurrentUser && claimantHandoverSignal == nil,
            mapAction: { selectedRootTab = .map },
            shareAction: openPublishSheet,
            garageAction: { selectedRootTab = .garage }
        )
    }

    private func presentClaimedHandover() {
        handoverNavigation.claimSheetDismissed()
    }

    private func claimantResumeCard(_ signal: ParkingSignal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You’re heading there")
                        .font(.headline)
                        .foregroundStyle(Color.spotTextPrimary)
                    Text("\(signal.campus.title) — \(signal.zone)")
                        .font(.subheadline)
                        .foregroundStyle(Color.spotTextSecondary)
                }
                Spacer()
                Text(signal.status.rawValue.capitalized)
                    .font(.caption2.bold())
                    .foregroundStyle(Color.spotAccentStrong)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.spotAccentSoft, in: Capsule())
            }
            Button("Resume Handover", systemImage: "arrow.up.forward.app.fill") {
                handoverNavigation.resume(signalID: signal.id)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.spotAccent)
        }
        .padding(15)
        .background(Color.spotSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.spotAccent.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct LiveHandoverDestination: View {
    @Environment(\.dismiss) private var dismiss
    let store: SignalStore
    let signalID: UUID
    let closed: () -> Void
    let completed: (ParkingSignal) -> Void

    private var signal: ParkingSignal? {
        store.signals.first {
            $0.id == signalID
                && ($0.createdBy == store.userID || $0.claimedBy == store.userID)
                && [.claimed, .arrived, .vacated].contains($0.status)
        }
    }

    var body: some View {
        Group {
            if let signal {
                LiveHandoverView(
                    store: store,
                    signal: signal,
                    close: close,
                    completed: completed
                )
            } else {
                ProgressView("Updating handover…")
                    .task {
                        closed()
                        dismiss()
                    }
            }
        }
    }

    private func close() {
        closed()
        dismiss()
    }
}
