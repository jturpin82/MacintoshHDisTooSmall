import SwiftUI
import AppKit

@MainActor
struct SettingsSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.fill")
                            .font(.title2)
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.destinationPath.isEmpty
                                 ? "Aucun dossier choisi"
                                 : PathFormat.short(state.destinationPath))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("Chaque app obtient son propre sous-dossier ici.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choisir…", action: chooseDestination)
                    }
                } header: {
                    Text("Destination")
                } footer: {
                    Text("Un volume externe ou un second disque interne. Si le volume n'est pas monté, les apps déplacées ne se lanceront pas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Laisser un lien symbolique dans /Applications", isOn: $state.createAppSymlink)
                } header: {
                    Text("Comportement")
                } footer: {
                    Text("Activé : l'app reste visible et lançable depuis /Applications, le Dock et Spotlight. Désactivé : /Applications est réellement vidé et l'app se lance depuis sa nouvelle adresse. Dans les deux cas les caches et configurations sont toujours remplacés par un lien, sinon l'app les recrée aussitôt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Terminé") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 420)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Dossier qui accueillera les applications déplacées"
        if !state.destinationPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: state.destinationPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            state.destinationPath = url.path
        }
    }
}
