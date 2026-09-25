import SwiftUI

struct CreateSignalView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasShownLocationPermissionExplanation") private var hasShownLocationExplanation = false

    let store: SignalStore
    let vehicleStore: VehicleStore
    let locationStore: LocationStore
    let zone: ParkingZone

    @State private var minutes = 5
    @State private var selectedVehicleID: UUID?
    @State private var showingLocationExplanation = false

    private var canPublish: Bool {
        PublishSignalEligibility.canPublish(
            vehicleID: selectedVehicleID,
            minutes: minutes,
            locationState: locationStore.verificationState,
            isPublishing: store.isPublishing
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Parking area") {
                    LabeledContent("Zone", value: zone.name)
                    LabeledContent("Landmark", value: zone.landmark)
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
                    Task { await locationStore.requestPermissionAndVerify(zone: zone) }
                } notNow: {
                    hasShownLocationExplanation = true
                    showingLocationExplanation = false
                }
                .presentationDetents([.medium])
            }
            .task {
                switch locationStore.authorizationState {
                case .authorized:
                    await locationStore.verify(zone: zone)
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
            case let .verified(result):
                Label("Verified at Campus A Student Car Park", systemImage: "checkmark.location.fill")
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
                        Task { await locationStore.requestPermissionAndVerify(zone: zone) }
                    } else {
                        showingLocationExplanation = true
                    }
                }
            } else if locationStore.authorizationState == .authorized {
                Button("Retry Location", systemImage: "location.magnifyingglass") {
                    Task { await locationStore.verify(zone: zone) }
                }
                .disabled(locationStore.verificationState == .locating)
            }
        }
    }

    private func publish() {
        guard canPublish else { return }
        Task {
            // A fresh reading immediately before the RPC limits stale submissions.
            await locationStore.verify(zone: zone)
            guard locationStore.verificationState.isVerified,
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
                await locationStore.verify(zone: zone)
            }
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
