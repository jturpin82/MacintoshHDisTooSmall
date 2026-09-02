import SwiftUI

struct SidebarView: View {
    @Bindable var state: AppState

    var body: some View {
        List(selection: $state.selectedRowID) {
            ForEach(state.visibleRows) { row in
                SidebarRow(row: row).tag(row.id)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $state.searchText, prompt: "Rechercher une app")
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("", selection: $state.filter) {
                ForEach(AppState.Filter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.secondary)
                Text(state.totalReclaimed > 0
                     ? "\(FileSize.format(state.totalReclaimed)) libérés"
                     : "Rien de déplacé pour l'instant")
                Spacer()
                if state.isScanning { ProgressView().controlSize(.small) }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
    }
}

private struct SidebarRow: View {
    let row: AppRow

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(path: row.iconPath, side: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).lineLimit(1)
                if row.isOrphaned {
                    Label("Non suivie", systemImage: "questionmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if row.isRelocated {
                    Label("Déplacée", systemImage: "arrow.uturn.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                } else if let version = row.app?.version {
                    Text(version)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if let size = row.size, size > 0 {
                Text(FileSize.format(size))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
