import SwiftUI

struct HandoverPassCard: View {
    let pass: HandoverDetails.Pass

    var body: some View {
        VStack(spacing: 12) {
            Text("HANDOVER PASS")
                .font(.caption.bold())
                .tracking(2)
            Image(systemName: pass.symbolName)
                .font(.system(size: 54, weight: .semibold))
            Text(pass.confirmationNumber)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(pass.title.uppercased())
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .foregroundStyle(.white)
        .background(passColor.gradient, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Handover pass \(pass.title)")
    }

    private var passColor: Color {
        switch pass.color {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow.mix(with: .orange, by: 0.25)
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}

struct HandoverPassView: View {
    @Environment(\.dismiss) private var dismiss
    let details: HandoverDetails

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let pass = details.pass { HandoverPassCard(pass: pass) }
                    VStack(spacing: 6) {
                        Text("Vehicle leaving").font(.caption).foregroundStyle(.secondary)
                        Text(details.ownerVehicle.description).font(.headline).multilineTextAlignment(.center)
                    }
                    Text("Show this pass to the departing driver so they can visually match the colour, symbol, number, and vehicle.")
                        .multilineTextAlignment(.center)
                    Label(
                        "Visually verify only when safely stopped. Do not block traffic or confront another driver.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Handover Pass")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
