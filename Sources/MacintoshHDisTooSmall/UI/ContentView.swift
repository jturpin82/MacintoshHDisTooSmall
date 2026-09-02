import SwiftUI

@MainActor
struct ContentView: View {
    @State private var state = AppState()

    var body: some View {
        NavigationSplitView {
            SidebarView(state: state)
        } detail: {
            DetailView(state: state)
        }
        .frame(minWidth: 940, minHeight: 580)
        .toolbar {
            ToolbarItem {
                Button { state.refresh() } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .disabled(state.isBusy)
            }
            ToolbarItem {
                Button { state.showSettings = true } label: {
                    Label("Réglages", systemImage: "gearshape")
                }
            }
        }
        .task { state.refresh() }
        .onChange(of: state.selectedRowID) { _, _ in
            if let row = state.selectedRow {
                state.loadSupportItems(for: row)
            }
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsSheet(state: state)
        }
        .alert("Opération impossible", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
        .overlay {
            if state.isBusy {
                ProgressOverlay(label: state.operationLabel, progress: state.operationProgress)
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } })
    }
}
