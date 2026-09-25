import SwiftUI

struct OnboardingFlowView: View {
    private enum Step { case welcome, location }

    let locationStore: LocationStore
    let completion: () -> Void
    @State private var step: Step = .welcome
    @State private var isRequestingLocation = false

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut) { step = .location }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            case .location:
                CampusBoundaryPermissionView(
                    isRequesting: isRequestingLocation,
                    backAction: { withAnimation(.easeInOut) { step = .welcome } },
                    enableAction: requestLocation,
                    notNowAction: completion
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .tint(Color.spotPurple)
    }

    private func requestLocation() {
        guard !isRequestingLocation else { return }
        isRequestingLocation = true
        Task {
            await locationStore.requestPermission()
            isRequestingLocation = false
            completion()
        }
    }
}
