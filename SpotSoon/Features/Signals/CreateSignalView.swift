import SwiftUI

struct CreateSignalView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasShownLocationPermissionExplanation") private var hasShownLocationExplanation = false

    let store: SignalStore
    let vehicleStore: VehicleStore
    let locationStore: LocationStore
    let zoneStore: ParkingZoneStore

    @State private var minutes = 5
    @State private var selectedVehicleID: UUID?
    @State private var showingLocationExplanation = false
    @State private var selectedZoneID: String

    init(
        store: SignalStore,
        vehicleStore: VehicleStore,
        locationStore: LocationStore,
        zoneStore: ParkingZoneStore,
        initialZone: ParkingZone
    ) {
        self.store = store
        self.vehicleStore = vehicleStore
        self.locationStore = locationStore
        self.zoneStore = zoneStore
        _selectedZoneID = State(initialValue: initialZone.id)
    }

    private var zone: ParkingZone? {
        zoneStore.zones.first { $0.id == selectedZoneID && $0.isActive }
    }

    private var suggestedZone: ParkingZone? {
        guard let id = locationStore.suggestedZoneID else { return nil }
        return zoneStore.zones.first { $0.id == id }
    }

    private var canPublish: Bool {
        guard let zone else { return false }
        return PublishSignalEligibility.canPublish(
            vehicleID: selectedVehicleID,
            minutes: minutes,
            locationState: locationStore.verificationState,
            isPublishing: store.isPublishing
        ) && locationStore.isVerified(for: zone.id)
            && !store.hasOpenSignalOwnedByCurrentUser
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Parking area") {
                    Picker("Zone", selection: Binding(
                        get: { selectedZoneID },
                        set: { switchZone(to: $0) }
                    )) {
                        ForEach(zoneStore.zones) { option in
                            Text(option.selectionLabel).tag(option.id)
                        }
                    }
                    if let zone {
                        LabeledContent("Selected", value: zone.name)
                        if let context = zone.alternativeContext {
                            LabeledContent("Context", value: context)
                        }
                        LabeledContent("Landmark", value: zone.landmark)
                    }
                    Text("The map circle represents the permitted student parking area, not an individual parking bay.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Picker("Leaving in", selection: $minutes) {
                    ForEach([2, 5, 10], id: \.self) { Text("\($0) minutes").tag($0) }
                }

                VehiclePickerView(
                    title: "Vehicle you’re leaving in",
                    store: vehicleStore,
                    selectedVehicleID: $selectedVehicleID
                )

                locationSection

                Section {
                    Button("Publish") { publish() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canPublish)
                }
                if let error = store.publishError { Text(error).foregroundStyle(.red) }
                if store.isPublishing { ProgressView("Publishing…") }
                if store.hasOpenSignalOwnedByCurrentUser {
                    Text("Finish or cancel your current parking signal before publishing another.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .disabled(store.isPublishing)
            .navigationTitle("Leaving signal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") { publish() }.disabled(!canPublish)
                }
            }
            .interactiveDismissDisabled(store.isPublishing)
            .sheet(isPresented: $showingLocationExplanation) {
                LocationPermissionExplanationView {
                    hasShownLocationExplanation = true
                    showingLocationExplanation = false
                    verifyAfterPermission()
                } notNow: {
                    hasShownLocationExplanation = true
                    showingLocationExplanation = false
                }
                .presentationDetents([.medium])
            }
            .task {
                guard let zone else { return }
                switch locationStore.authorizationState {
                case .authorized:
                    await locationStore.verify(zone: zone, availableZones: zoneStore.zones)
                case .notRequested where !hasShownLocationExplanation:
                    showingLocationExplanation = true
                case .notRequested, .denied, .restricted:
                    break
                }
            }
        }
    }

    @ViewBuilder private var locationSection: some View {
        Section("Location verification") {
            switch locationStore.verificationState {
            case .notRequested:
                Label("Location permission has not been requested", systemImage: "location.slash")
            case .permissionDenied:
                Label("Location access denied", systemImage: "location.slash.fill")
                    .foregroundStyle(.red)
                Button("Open Settings") { locationStore.openSettings() }
            case .restricted:
                Label("Location access restricted", systemImage: "lock.fill")
                    .foregroundStyle(.red)
            case .locating:
                ProgressView("Getting a fresh GPS reading…")
            case let .inaccurate(accuracy):
                Label("GPS reading is too inaccurate", systemImage: "scope")
                    .foregroundStyle(.orange)
                Text("Current accuracy: ±\(Int(accuracy.rounded())) m. Required: 65 m or better.")
            case let .outsideZone(distance, accuracy):
                Label("Outside parking zone", systemImage: "mappin.slash")
                    .foregroundStyle(.orange)
                Text("Approximately \(Int(distance.rounded())) m from the zone centre · accuracy ±\(Int(accuracy.rounded())) m")
                if let suggestedZone {
                    Text("You appear to be near \(suggestedZone.name)")
                        .font(.subheadline.weight(.medium))
                    Button("Switch to \(suggestedZone.campus.title)") {
                        switchZone(to: suggestedZone.id)
                    }
                }
            case let .verified(result):
                Label("Verified at \(zone?.name ?? "selected parking area")", systemImage: "checkmark.location.fill")
                    .foregroundStyle(.green)
                if let distance = result.distanceMeters {
                    Text("Approximately \(Int(distance.rounded())) m from centre · accuracy ±\(Int(result.horizontalAccuracy.rounded())) m")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            case .unavailable:
                Label("Location unavailable", systemImage: "location.slash")
                    .foregroundStyle(.orange)
            case let .error(message):
                Text(message).foregroundStyle(.red)
            }

            if locationStore.authorizationState == .notRequested {
                Button("Allow Location") {
                    if hasShownLocationExplanation {
                        verifyAfterPermission()
                    } else {
                        showingLocationExplanation = true
                    }
                }
            } else if locationStore.authorizationState == .authorized {
                Button("Retry Location", systemImage: "location.magnifyingglass") {
                    verifySelectedZone()
                }
                .disabled(locationStore.verificationState == .locating)
            }
        }
    }

    private func publish() {
        guard canPublish, let zone else { return }
        Task {
            // A fresh reading immediately before the RPC limits stale submissions.
            await locationStore.verify(zone: zone, availableZones: zoneStore.zones)
            guard locationStore.isVerified(for: zone.id),
                  let reading = locationStore.latestReading else { return }
            let succeeded = await store.publish(
                zone: zone,
                minutes: minutes,
                ownerVehicleID: selectedVehicleID,
                location: reading
            )
            if succeeded {
                dismiss()
            } else if store.publishRequiresLocationRefresh {
                await locationStore.verify(zone: zone, availableZones: zoneStore.zones)
            }
        }
    }

    private func switchZone(to id: String) {
        guard id != selectedZoneID,
              let newZone = zoneStore.zones.first(where: { $0.id == id && $0.isActive }) else {
            return
        }
        selectedZoneID = id
        _ = zoneStore.selectZone(id: id)
        locationStore.invalidateVerification()
        if locationStore.authorizationState == .authorized {
            Task {
                await locationStore.switchAndVerify(
                    to: newZone,
                    availableZones: zoneStore.zones
                )
            }
        }
    }

    private func verifySelectedZone() {
        guard let zone else { return }
        Task { await locationStore.verify(zone: zone, availableZones: zoneStore.zones) }
    }

    private func verifyAfterPermission() {
        guard let zone else { return }
        Task {
            await locationStore.requestPermissionAndVerify(
                zone: zone,
                availableZones: zoneStore.zones
            )
        }
    }
}

nonisolated enum PublishSignalEligibility {
    static func canPublish(
        vehicleID: UUID?,
        minutes: Int,
        locationState: LocationStore.VerificationState,
        isPublishing: Bool
    ) -> Bool {
        vehicleID != nil
            && [2, 5, 10].contains(minutes)
            && locationState.isVerified
            && !isPublishing
    }
}
