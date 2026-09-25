import SwiftUI

struct SettingsView: View {
    let vehicleStore: VehicleStore
    let locationStore: LocationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Account & Settings")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.spotInk)

                section("ACCOUNT") { accountCard }

                section("PARKING & VEHICLES") {
                    card {
                        NavigationLink { GarageView(store: vehicleStore) } label: {
                            SettingsRow(icon: "car.2.fill", iconColor: .spotPurple, title: "My Garage", value: "\(vehicleStore.vehicles.count) saved")
                        }
                        Divider().padding(.leading, 46)
                        NavigationLink { GarageView(store: vehicleStore) } label: {
                            SettingsRow(
                                icon: "car.fill",
                                iconColor: .spotPurple,
                                title: "Today’s Vehicle",
                                subtitle: vehicleStore.currentVehicle?.nickname ?? "No vehicle selected",
                                badge: vehicleStore.currentVehicle == nil ? nil : "ACTIVE"
                            )
                        }
                        Divider().padding(.leading, 46)
                        Button {
                            if locationStore.authorizationState == .denied {
                                locationStore.openSettings()
                            } else if locationStore.authorizationState == .notRequested {
                                Task { await locationStore.requestPermission() }
                            }
                        } label: {
                            SettingsRow(
                                icon: "location.fill",
                                iconColor: .blue,
                                title: "Location Access",
                                value: locationStore.authorizationState.title,
                                showsChevron: locationStore.authorizationState != .restricted
                            )
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "building.2.fill", iconColor: .orange, title: "Default Campus", value: "Selected on map", showsChevron: false)
                    }
                }

                section("SAFETY & PRIVACY") {
                    card {
                        SettingsRow(icon: "lock.fill", iconColor: .green, title: "Location & Privacy", subtitle: "Location is used only for zone verification.", showsChevron: false)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "shield.lefthalf.filled", iconColor: .spotPurple, title: "Handover Safety", value: "Protected", showsChevron: false)
                    }
                    Text("Vehicle details and the three-character plate suffix are shared only with the other participant during an active handover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                }

                section("SUPPORT & ABOUT") {
                    card {
                        SettingsRow(icon: "questionmark.circle.fill", iconColor: .purple, title: "Help & FAQ", value: "Coming later", showsChevron: false)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "exclamationmark.triangle.fill", iconColor: .orange, title: "Report a Problem", value: "Coming later", showsChevron: false)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "info.circle.fill", iconColor: .blue, title: "About SpotSoon", subtitle: "Campus parking handovers", showsChevron: false)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "apps.iphone", iconColor: .gray, title: "App Version", value: "Technical preview", showsChevron: false)
                    }
                }

                Text("SpotSoon for campus parking")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            locationStore.refreshAuthorizationState()
            if vehicleStore.vehicles.isEmpty { await vehicleStore.load() }
        }
    }

    private var accountCard: some View {
        card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.spotLavender)
                    Image(systemName: "person.fill").foregroundStyle(Color.spotPurple)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Anonymous account").font(.headline).foregroundStyle(Color.spotInk)
                    Text("Private Supabase session").font(.caption).foregroundStyle(.secondary)
                    Label("Campus SSO coming later", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                Spacer()
            }
            .padding(14)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(.background, in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(Color.primary.opacity(0.05), lineWidth: 1) }
    }
}

private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var badge: String? = nil
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.spotInk)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
