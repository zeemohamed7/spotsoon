import SwiftUI

struct SettingsView: View {
    let vehicleStore: VehicleStore
    let locationStore: LocationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Account & Settings")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.spotTextPrimary)

                section("ACCOUNT") { accountCard }

                section("PARKING & VEHICLES") {
                    card {
                        NavigationLink { GarageView(store: vehicleStore) } label: {
                            SettingsRow(icon: "car.2.fill", iconColor: .spotAccent, title: "My Garage", value: "\(vehicleStore.vehicles.count) saved")
                        }
                        Divider().padding(.leading, 46)
                        NavigationLink { GarageView(store: vehicleStore) } label: {
                            SettingsRow(
                                icon: "car.fill",
                                iconColor: .spotAccent,
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
                                iconColor: .spotAccent,
                                title: "Location Access",
                                value: locationStore.authorizationState.title,
                                showsChevron: locationStore.authorizationState != .restricted
                            )
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "building.2.fill", iconColor: .spotWarning, title: "Default Campus", value: "Selected on map", showsChevron: false)
                    }
                }

                section("SAFETY & PRIVACY") {
                    card {
                        SettingsRow(icon: "lock.fill", iconColor: .spotSuccess, title: "Location & Privacy", subtitle: "Zone verification plus optional foreground approach sharing.", showsChevron: false)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "shield.lefthalf.filled", iconColor: .spotAccent, title: "Handover Safety", value: "Protected", showsChevron: false)
                    }
                    Text("Temporary approximate coordinates are participant-protected and cleared when access ends. GPS does not identify an exact bay; use the private hint, vehicles, partial plate suffix, and matching pass.")
                        .font(.caption)
                        .foregroundStyle(Color.spotTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                }

                section("SUPPORT & ABOUT") {
                    card {
                        SettingsRow(icon: "questionmark.circle.fill", iconColor: .spotAccentStrong, title: "Help & FAQ", value: "Coming later", showsChevron: false)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "exclamationmark.triangle.fill", iconColor: .spotWarning, title: "Report a Problem", value: "Coming later", showsChevron: false)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "info.circle.fill", iconColor: .spotAccent, title: "About SpotSoon", subtitle: "Campus parking handovers", showsChevron: false)
                        Divider().padding(.leading, 46)
                        SettingsRow(icon: "apps.iphone", iconColor: .spotTextMuted, title: "App Version", value: "Technical preview", showsChevron: false)
                    }
                }

                Text("SpotSoon for campus parking")
                    .font(.caption2)
                    .foregroundStyle(Color.spotTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding(20)
        }
        .spotScreenBackground(grouped: true)
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
                    Circle().fill(Color.spotAccentSoft)
                    Image(systemName: "person.fill").foregroundStyle(Color.spotAccent)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Anonymous account").font(.headline).foregroundStyle(Color.spotTextPrimary)
                    Text("Private Supabase session").font(.caption).foregroundStyle(Color.spotTextSecondary)
                    Label("Campus SSO coming later", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.spotAccent)
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
                .foregroundStyle(Color.spotTextSecondary)
                .padding(.horizontal, 6)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .spotCard(radius: 15)
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
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.spotTextPrimary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.spotSuccess)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.spotSuccess.opacity(0.12), in: Capsule())
                    }
                }
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Color.spotTextSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.caption).foregroundStyle(Color.spotTextSecondary).multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.spotTextMuted)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
