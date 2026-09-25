import SwiftUI

struct VehicleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let store: VehicleStore
    let vehicle: Vehicle?
    let onSaved: (Vehicle) -> Void
    private let originalDraft: VehicleDraft

    @State private var draft: VehicleDraft
    @State private var showingDiscardConfirmation = false

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Nickname", text: $draft.nickname)
                        .textInputAutocapitalization(.words)
                    TextField("Colour", text: $draft.color)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $draft.vehicleType) {
                        ForEach(Vehicle.VehicleType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    TextField("Make (optional)", text: $draft.make)
                        .textInputAutocapitalization(.words)
                    TextField("Model (optional)", text: $draft.model)
                        .textInputAutocapitalization(.words)
                    TextField("Final 1–3 plate characters (optional)", text: $draft.plateSuffix)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Text("Never enter a complete licence plate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Use as Today’s Vehicle", isOn: $draft.useAsCurrent)
                        .disabled(vehicle?.isCurrent == true)
                }

                if let error = store.editorError {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button(vehicle == nil ? "Add Vehicle" : "Save Changes") { save() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isSaving)
                    if store.isSaving { ProgressView("Saving vehicle…") }
                }
            }
            .navigationTitle(vehicle == nil ? "Add Vehicle" : "Edit Vehicle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges { showingDiscardConfirmation = true }
                        else { dismiss() }
                    }
                    .disabled(store.isSaving)
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges || store.isSaving)
            .confirmationDialog("Discard unsaved changes?", isPresented: $showingDiscardConfirmation) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
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
}
