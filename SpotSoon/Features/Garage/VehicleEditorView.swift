import SwiftUI

struct VehicleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let store: VehicleStore
    let vehicle: Vehicle?
    let onSaved: (Vehicle) -> Void
    private let originalDraft: VehicleDraft

    @State private var draft: VehicleDraft
    @State private var showingDiscardConfirmation = false
    @State private var showingDeleteConfirmation = false

    private let presetColors = ["White", "Silver", "Grey", "Black", "Blue", "Red", "Orange"]

    init(store: VehicleStore, vehicle: Vehicle? = nil, onSaved: @escaping (Vehicle) -> Void = { _ in }) {
        self.store = store
        self.vehicle = vehicle
        self.onSaved = onSaved
        var initial = vehicle.map(VehicleDraft.init) ?? VehicleDraft()
        if vehicle == nil && store.vehicles.isEmpty { initial.useAsCurrent = true }
        originalDraft = initial
        _draft = State(initialValue: initial)
    }

    private var hasUnsavedChanges: Bool { draft != originalDraft }
    private var isBusy: Bool {
        store.isSaving || (vehicle.map { store.isWorking(on: $0.id) } ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("VEHICLE INFO") { vehicleInfoCard }
                    section("VEHICLE TYPE") { vehicleTypePicker }
                    section("VEHICLE COLOUR") { colorPicker }
                    section("PLATE RECOGNITION") { plateCard }
                    section("PREFERENCES") { preferenceCard }

                    if let error = store.editorError ?? store.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                    }

                    Button(action: save) {
                        HStack(spacing: 9) {
                            if store.isSaving { ProgressView().tint(.white) }
                            Text(vehicle == nil ? "Save Vehicle" : "Save Changes")
                        }
                    }
                    .buttonStyle(SpotSoonPrimaryButtonStyle())
                    .disabled(isBusy)

                    if vehicle != nil {
                        Button("Delete Vehicle", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .disabled(isBusy)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(vehicle == nil ? "Add Vehicle" : "Edit Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { requestDismiss() }.disabled(isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges || isBusy)
            .confirmationDialog("Discard unsaved changes?", isPresented: $showingDiscardConfirmation) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete \(vehicle?.nickname ?? "vehicle")?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Vehicle", role: .destructive) { deleteVehicle() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Active handovers keep their saved vehicle snapshot. If this is Today’s Vehicle, another saved vehicle will be selected automatically.")
            }
        }
    }

    private var vehicleInfoCard: some View {
        VStack(spacing: 0) {
            editorRow("Nickname") {
                TextField("My K5", text: $draft.nickname)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            Divider().padding(.leading, 14)
            editorRow("Make") {
                TextField("Kia (optional)", text: $draft.make)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            Divider().padding(.leading, 14)
            editorRow("Model") {
                TextField("K5 (optional)", text: $draft.model)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
        }
        .cardStyle()
    }

    private var vehicleTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Vehicle.VehicleType.allCases, id: \.self) { type in
                    Button {
                        draft.vehicleType = type
                    } label: {
                        Label(type.title, systemImage: vehicleIcon(type))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(draft.vehicleType == type ? .white : Color.spotInk)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(draft.vehicleType == type ? Color.spotPurple : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 15) {
                ForEach(presetColors, id: \.self) { color in
                    Button {
                        draft.color = color
                    } label: {
                        Circle()
                            .fill(swatchColor(color))
                            .frame(width: 31, height: 31)
                            .padding(3)
                            .overlay {
                                Circle()
                                    .stroke(draft.color.caseInsensitiveCompare(color) == .orderedSame ? Color.spotPurple : Color.primary.opacity(0.12), lineWidth: draft.color.caseInsensitiveCompare(color) == .orderedSame ? 2 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            HStack {
                Text("Colour name").font(.subheadline)
                Spacer()
                TextField("e.g. Midnight Grey", text: $draft.color)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
        }
        .padding(14)
        .cardStyle()
    }

    private var plateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Final 3 Characters", systemImage: "rectangle.and.pencil.and.ellipsis")
                    .font(.subheadline.weight(.medium))
                Spacer()
                HStack(spacing: 8) {
                    Text("•••").foregroundStyle(.secondary)
                    TextField("404", text: plateBinding)
                        .frame(width: 48)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .font(.subheadline.monospaced())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            Text("Never enter a full licence plate. SpotSoon only needs the final three characters for identification.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .cardStyle()
    }

    private var preferenceCard: some View {
        Toggle(isOn: $draft.useAsCurrent) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Use as Today’s Vehicle").font(.subheadline.weight(.medium))
                Text("Automatically selects this car for active signals.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(Color.spotPurple)
        .padding(14)
        .cardStyle()
        .disabled(vehicle?.isCurrent == true)
    }

    private var plateBinding: Binding<String> {
        Binding(
            get: { draft.plateSuffix },
            set: { value in
                let filtered = value.uppercased().filter { character in
                    character.isASCII && (character.isLetter || character.isNumber)
                }
                draft.plateSuffix = String(filtered.prefix(3))
            }
        )
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer(minLength: 16)
            content().font(.subheadline).foregroundStyle(Color.spotInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func requestDismiss() {
        if hasUnsavedChanges { showingDiscardConfirmation = true }
        else { dismiss() }
    }

    private func save() {
        Task {
            if await store.save(draft, editing: vehicle),
               let savedID = store.lastSavedVehicleID,
               let saved = store.vehicles.first(where: { $0.id == savedID }) {
                onSaved(saved)
                dismiss()
            }
        }
    }

    private func deleteVehicle() {
        guard let vehicle else { return }
        Task {
            if await store.delete(vehicle) { dismiss() }
        }
    }

    private func vehicleIcon(_ type: Vehicle.VehicleType) -> String {
        switch type {
        case .sedan: "car.side.fill"
        case .suv: "suv.side.fill"
        case .hatchback: "car.side.fill"
        case .pickup: "truck.pickup.side.fill"
        case .van: "bus.fill"
        case .other: "car.fill"
        }
    }

    private func swatchColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "white": .white
        case "silver": Color(white: 0.8)
        case "grey", "gray", "midnight grey", "midnight gray": Color(white: 0.4)
        case "black": Color.spotInk
        case "blue": .blue
        case "red": .red
        case "orange": .orange
        default: .secondary
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06), lineWidth: 1) }
    }
}
