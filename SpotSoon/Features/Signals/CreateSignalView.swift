import SwiftUI

struct CreateSignalView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasShownLocationPermissionExplanation") private var hasShownLocationExplanation = false

    let store: SignalStore
    let vehicleStore: VehicleStore
    let locationStore: LocationStore
    let zoneStore: ParkingZoneStore

    @State private var minutes = 2
    @State private var selectedVehicleID: UUID?
    @State private var bayHint = ""
    @State private var didPublish = false
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
            ?? ParkingZone.supportedDefaults.first { $0.id == selectedZoneID }
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
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        departurePicker

                        VehiclePickerView(
                            title: "Vehicle you’re leaving in",
                            store: vehicleStore,
                            selectedVehicleID: $selectedVehicleID
                        )

                        Text("Only revealed to the claimant during the active handover.")
                            .font(.caption)
                            .foregroundStyle(Color.spotTextSecondary)
                            .padding(.top, -16)

                        bayHintField
                        locationStatus

                        if let error = store.publishError {
                            Text(error).font(.caption).foregroundStyle(Color.spotError)
                        }
                        if store.hasOpenSignalOwnedByCurrentUser && !store.isPublishing && !didPublish {
                            Text("Finish or cancel your current signal before publishing another.")
                                .font(.caption).foregroundStyle(Color.spotError)
                        }

                        HStack {
                            Spacer()
                            Label(
                                "Expires in \(minutes == 0 ? 5 : minutes + 5) min if unclaimed",
                                systemImage: "clock"
                            )
                            .font(.caption)
                            .foregroundStyle(Color.spotTextSecondary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)

                Divider().overlay(Color.spotBorder)
                publishFooter
            }
            .spotScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .disabled(store.isPublishing)
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

    private var publishFooter: some View {
        Button {
            publish()
        } label: {
            if store.isPublishing {
                ProgressView().tint(Color.spotAccentForeground)
            } else {
                Label("Publish Signal", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .buttonStyle(SpotSoonPrimaryButtonStyle())
        .disabled(!canPublish)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.spotBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Publish Signal")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.spotTextPrimary)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(Color.spotTextSecondary)
                    .frame(width: 42, height: 42)
                    .background(Color.spotSurfaceElevated, in: Circle())
            }

            if let zone {
                Menu {
                    ForEach(zoneStore.zones.isEmpty ? ParkingZone.supportedDefaults : zoneStore.zones) { option in
                        Button(option.selectionLabel) { switchZone(to: option.id) }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text("\(zone.campus.title) — \(zone.name)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.spotTextPrimary)
                        Text("·")
                        Label(verificationLabel, systemImage: "circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(locationStore.isVerified(for: zone.id) ? Color.spotSuccess : Color.spotWarning)
                    }
                }
            }
        }
    }

    private var verificationLabel: String {
        guard let zone else { return "Not verified" }
        return locationStore.isVerified(for: zone.id) ? "Verified in zone" : "Verification needed"
    }

    private var departurePicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("DEPARTING IN")
                .font(.caption.bold())
                .foregroundStyle(Color.spotTextSecondary)
            HStack(spacing: 9) {
                ForEach([0, 2, 5, 10], id: \.self) { option in
                    Button(option == 0 ? "Now" : "\(option) min") { minutes = option }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(minutes == option ? Color.spotAccentForeground : Color.spotTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            minutes == option ? Color.spotAccent : Color.spotSurfaceElevated,
                            in: Capsule()
                        )
                }
            }
        }
    }

    private var bayHintField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BAY OR LANDMARK HINT (OPTIONAL)")
                .font(.caption.bold())
                .foregroundStyle(Color.spotTextSecondary)
            TextField("e.g. Row 3, near shade canopy", text: $bayHint, axis: .vertical)
                .lineLimit(2...3)
                .padding(15)
                .background(Color.spotInputBackground, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.spotBorder, lineWidth: 1)
                }
                .onChange(of: bayHint) { _, value in
                    if value.count > ParkingHint.maximumLength {
                        bayHint = String(value.prefix(ParkingHint.maximumLength))
                    }
                }
            Text("Visible only to you and the driver who successfully claims your signal.")
                .font(.caption)
                .foregroundStyle(Color.spotTextSecondary)
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch locationStore.verificationState {
            case .notRequested:
                Label("Location verification required", systemImage: "location")
            case .permissionDenied:
                Label("Location access denied", systemImage: "location.slash.fill").foregroundStyle(Color.spotError)
                Button("Open Settings") { locationStore.openSettings() }
            case .restricted:
                Label("Location access restricted", systemImage: "lock.fill").foregroundStyle(Color.spotError)
            case .locating:
                ProgressView("Verifying parking area…")
            case let .inaccurate(accuracy):
                Label("GPS accuracy ±\(Int(accuracy.rounded())) m is too low", systemImage: "scope")
                    .foregroundStyle(Color.spotWarning)
            case let .outsideZone(distance, _):
                Label("Outside selected zone · \(Int(distance.rounded())) m away", systemImage: "mappin.slash")
                    .foregroundStyle(Color.spotWarning)
                if let suggestedZone {
                    Button("Switch to \(suggestedZone.campus.title)") { switchZone(to: suggestedZone.id) }
                }
            case .verified:
                Label("Campus location verified", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.spotSuccess)
            case .unavailable:
                Label("Location unavailable", systemImage: "location.slash").foregroundStyle(Color.spotWarning)
            case let .error(message):
                Text(message).foregroundStyle(Color.spotError)
            }

            if locationStore.authorizationState == .notRequested {
                Button("Enable Campus Location") {
                    if hasShownLocationExplanation { verifyAfterPermission() }
                    else { showingLocationExplanation = true }
                }
            } else if locationStore.authorizationState == .authorized {
                Button("Retry Verification", systemImage: "location.magnifyingglass") { verifySelectedZone() }
                    .disabled(locationStore.verificationState == .locating)
            }
        }
        .font(.subheadline)
    }

    private func publish() {
        guard canPublish, let zone else { return }
        Task {
            await locationStore.verify(zone: zone, availableZones: zoneStore.zones)
            guard locationStore.isVerified(for: zone.id), let reading = locationStore.latestReading else { return }
            let succeeded = await store.publish(
                zone: zone,
                minutes: minutes,
                ownerVehicleID: selectedVehicleID,
                location: reading,
                bayHint: bayHint
            )
            if succeeded {
                didPublish = true
                dismiss()
            }
            else if store.publishRequiresLocationRefresh {
                await locationStore.verify(zone: zone, availableZones: zoneStore.zones)
            }
        }
    }

    private func switchZone(to id: String) {
        guard id != selectedZoneID,
              let newZone = (zoneStore.zones.isEmpty ? ParkingZone.supportedDefaults : zoneStore.zones)
                .first(where: { $0.id == id && $0.isActive }) else { return }
        selectedZoneID = id
        _ = zoneStore.selectZone(id: id)
        locationStore.invalidateVerification()
        if locationStore.authorizationState == .authorized {
            Task { await locationStore.switchAndVerify(to: newZone, availableZones: zoneStore.zones) }
        }
    }

    private func verifySelectedZone() {
        guard let zone else { return }
        Task { await locationStore.verify(zone: zone, availableZones: zoneStore.zones) }
    }

    private func verifyAfterPermission() {
        guard let zone else { return }
        Task {
            await locationStore.requestPermissionAndVerify(zone: zone, availableZones: zoneStore.zones)
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
            && [0, 2, 5, 10].contains(minutes)
            && locationState.isVerified
            && !isPublishing
    }
}
