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
                            .foregroundStyle(Color.spotError)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.spotError.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                    }

                    Button(action: save) {
                        HStack(spacing: 9) {
                            if store.isSaving { ProgressView().tint(Color.spotAccentForeground) }
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
            .spotScreenBackground(grouped: true)
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
        .spotCard(radius: 14)
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
                            .foregroundStyle(draft.vehicleType == type ? Color.spotAccentForeground : Color.spotTextPrimary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(draft.vehicleType == type ? Color.spotAccent : Color.spotSurfaceElevated, in: Capsule())
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
                                    .stroke(draft.color.caseInsensitiveCompare(color) == .orderedSame ? Color.spotAccent : Color.spotBorder, lineWidth: draft.color.caseInsensitiveCompare(color) == .orderedSame ? 2 : 1)
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
        .spotCard(radius: 14)
    }

    private var plateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Final 3 Characters", systemImage: "rectangle.and.pencil.and.ellipsis")
                    .font(.subheadline.weight(.medium))
                Spacer()
                HStack(spacing: 8) {
                    Text("•••").foregroundStyle(Color.spotTextSecondary)
                    TextField("404", text: plateBinding)
                        .frame(width: 48)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .font(.subheadline.monospaced())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.spotInputBackground, in: RoundedRectangle(cornerRadius: 10))
            }

            Text("Never enter a full licence plate. SpotSoon only needs the final three characters for identification.")
                .font(.caption)
                .foregroundStyle(Color.spotTextSecondary)
        }
        .padding(14)
        .spotCard(radius: 14)
    }

    private var preferenceCard: some View {
        Toggle(isOn: $draft.useAsCurrent) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Use as Today’s Vehicle").font(.subheadline.weight(.medium))
                Text("Automatically selects this car for active signals.")
                    .font(.caption).foregroundStyle(Color.spotTextSecondary)
            }
        }
        .tint(Color.spotAccent)
        .padding(14)
        .spotCard(radius: 14)
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
                .foregroundStyle(Color.spotTextSecondary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer(minLength: 16)
            content().font(.subheadline).foregroundStyle(Color.spotTextPrimary)
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
        case "black": Color.black
        case "blue": .blue
        case "red": .red
        case "orange": .orange
        default: .secondary
        }
    }
}
