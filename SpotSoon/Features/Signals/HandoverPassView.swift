import SwiftUI

struct HandoverPassCard: View {
    let pass: HandoverDetails.Pass

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("DASHBOARD MODE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .tracking(1)
                Spacer()
                Text("Brightness 100%")
                    .font(.caption)
            }
            Image(systemName: pass.symbolName)
                .font(.system(size: 72, weight: .semibold))
                .frame(width: 130, height: 130)
                .background(.white.opacity(0.12), in: Circle())
            Text(pass.confirmationNumber)
                .font(.system(size: 94, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(pass.title.uppercased())
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .tracking(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .foregroundStyle(.white)
        .background(passColor.gradient, in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: passColor.opacity(0.28), radius: 22, y: 12)
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
        VStack(spacing: 12) {
            HStack {
                Label("LIVE HANDOVER BEACON", systemImage: "circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Color.spotPurpleDark)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.spotPurple.opacity(0.1), in: Capsule())
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Color.spotLavender, in: Circle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            ScrollView {
                VStack(spacing: 24) {
                    if let pass = details.pass { HandoverPassCard(pass: pass) }
                    HStack(spacing: 12) {
                        Image(systemName: "car.fill")
                            .foregroundStyle(Color.spotPurple)
                            .frame(width: 44, height: 44)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("VEHICLE LEAVING")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(details.ownerVehicle.description)
                                .font(.headline)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.spotLavender, in: RoundedRectangle(cornerRadius: 18))
                    Text("Show this pass to the departing driver so they can visually match the colour, symbol, number, and vehicle.")
                        .multilineTextAlignment(.center)
                    Label(
                        "Visually verify only when safely stopped. Do not block traffic or confront another driver.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Button("I See the Driver’s Vehicle", systemImage: "eye.fill") {
                        dismiss()
                    }
                    .buttonStyle(SpotSoonPrimaryButtonStyle())
                }
                .padding(20)
            }
        }
        .background(Color.spotLavender.opacity(0.35).ignoresSafeArea())
    }
}
