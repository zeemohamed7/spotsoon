import SwiftUI

struct SignalListView: View {
    let store: SignalStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingCreate = false
    @State private var retryID = UUID()
    @State private var signalToClaim: ParkingSignal?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let visible = ParkingSignal.visible(store.signals, at: context.date)
                List {
                    Button("Create leaving signal", systemImage: "plus") {
                        store.publishError = nil
                        showingCreate = true
                    }
                    if let error = store.connectionError {
                        Text(error).foregroundStyle(.red)
                        Button("Retry live updates") { retryID = UUID() }
                    }
                    if let error = store.listError { Text(error).foregroundStyle(.red) }
                    if store.isLoading { ProgressView("Loading signals…") }
                    if visible.isEmpty && !store.isLoading && store.listError == nil {
                        Text("No active signals. Publish one when you’re about to leave.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visible) { signal in
                        let presentation = signal.claimPresentation(for: store.userID)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(signal.campus.title) · \(signal.zone)").font(.headline)
                            if signal.leavingAt > context.date {
                                Text("Leaving in \(Int(ceil(signal.leavingAt.timeIntervalSince(context.date) / 60))) min")
                            } else {
                                Text("Leaving time reached")
                            }
                            Text("Status: \(signal.status.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(presentation.message)
                                .font(.subheadline)
                            if presentation.canClaim {
                                Button {
                                    signalToClaim = signal
                                } label: {
                                    if store.isClaiming(signal.id) {
                                        HStack {
                                            ProgressView()
                                            Text("Claiming…")
                                        }
                                    } else {
                                        Text("Claim")
                                    }
                                }
                                .disabled(store.isClaiming(signal.id))
                            }
                            if let error = store.claimErrors[signal.id] {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
                .refreshable { await store.refresh() }
            }
            .navigationTitle("SpotSoon")
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } } }
            .sheet(isPresented: $showingCreate) { CreateSignalView(store: store) }
            .alert("Claim this parking signal?", isPresented: Binding(
                get: { signalToClaim != nil },
                set: { if !$0 { signalToClaim = nil } }
            ), presenting: signalToClaim) { signal in
                Button("Cancel", role: .cancel) { signalToClaim = nil }
                Button("Claim") {
                    signalToClaim = nil
                    Task { await store.claim(signal) }
                }
            } message: { signal in
                Text("Confirm that you want to head to \(signal.campus.title), zone \(signal.zone).")
            }
        }
        .task(id: "\(scenePhase == .active)-\(retryID)") {
            if scenePhase == .active { await store.run() }
        }
    }
}
