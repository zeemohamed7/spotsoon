import SwiftUI

enum SpotSoonRootTab: Hashable {
    case map
    case garage
}

struct SpotSoonBottomNavigationBar: View {
    let selection: SpotSoonRootTab
    let canShare: Bool
    let mapAction: () -> Void
    let shareAction: () -> Void
    let garageAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton("Map", systemImage: "location.north", tab: .map, action: mapAction)

            Button(action: shareAction) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.spotAccentForeground)
                    .frame(width: 58, height: 58)
                    .background(Color.spotAccent.gradient, in: Circle())
                    .shadow(color: Color.spotAccent.opacity(0.3), radius: 13, y: 7)
            }
            .buttonStyle(.plain)
            .disabled(!canShare)
            .opacity(canShare ? 1 : 0.5)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Share your spot")
            .accessibilityHint(canShare ? "Opens the publish signal form" : "Finish your current signal first")

            tabButton("Garage", systemImage: "car.2.fill", tab: .garage, action: garageAction)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 330)
        .background(Color.spotSurface.opacity(0.98), in: Capsule())
        .overlay {
            Capsule().stroke(Color.spotBorder, lineWidth: 1)
        }
        .shadow(color: Color.spotOverlay.opacity(0.22), radius: 20, y: 9)
    }

    private func tabButton(
        _ title: String,
        systemImage: String,
        tab: SpotSoonRootTab,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                Text(title)
                    .font(.caption.weight(selection == tab ? .semibold : .regular))
            }
            .foregroundStyle(selection == tab ? Color.spotAccent : Color.spotTextSecondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
