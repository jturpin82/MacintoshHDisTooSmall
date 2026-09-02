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
                Menu {
                    Picker("Trier", selection: $state.sortOrder) {
                        ForEach(AppState.SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Trier", systemImage: "arrow.up.arrow.down")
                }
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
        .confirmationDialog("Supprimer \(state.deletionSummary?.name ?? "cette app") ?",
                            isPresented: $state.showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Mettre à la corbeille", role: .destructive) { state.deleteSelected() }
            Button("Annuler", role: .cancel) {}
        } message: {
            if let summary = state.deletionSummary {
                Text("\(summary.itemCount) élément(s) — \(FileSize.format(summary.bytes)). Si l'app appartient à root, une authentification sera demandée et la suppression sera alors définitive : la corbeille n'est pas utilisable en mode privilégié.")
            }
        }
        .confirmationDialog("Oublier le suivi de \(state.selectedRow?.name ?? "cette app") ?",
                            isPresented: $state.showForgetConfirmation,
                            titleVisibility: .visible) {
            Button("Oublier", role: .destructive) { state.forgetSelectedRecord() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Aucun fichier n'est touché : l'app et ses fichiers annexes restent exactement où ils sont. Seule disparaît la mémoire du déplacement, donc la possibilité de le défaire depuis cette app.")
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
