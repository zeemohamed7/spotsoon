import SwiftUI

struct SignalListView: View {
    let store: SignalStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingCreate = false
    @State private var retryID = UUID()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let visible = ParkingSignal.active(store.signals, at: context.date)
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(signal.campus.title) · \(signal.zone)").font(.headline)
                            if signal.leavingAt > context.date {
                                Text("Leaving in \(Int(ceil(signal.leavingAt.timeIntervalSince(context.date) / 60))) min")
                            } else {
                                Text("Leaving time reached")
                            }
                            Text("Status: \(signal.status.rawValue)\(signal.createdBy == store.userID ? " · Your signal" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .refreshable { await store.refresh() }
            }
            .navigationTitle("SpotSoon")
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } } }
            .sheet(isPresented: $showingCreate) { CreateSignalView(store: store) }
        }
        .task(id: "\(scenePhase == .active)-\(retryID)") {
            if scenePhase == .active { await store.run() }
        }
    }
}
