import SwiftUI
import AppKit

struct DetailView: View {
    @Bindable var state: AppState

    var body: some View {
        if let row = state.selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(row)
                    if let record = row.record {
                        RelocatedSection(state: state, record: record)
                    } else {
                        MoveSection(state: state, row: row)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(row.name)
        } else {
            ContentUnavailableView("Aucune application sélectionnée",
                                   systemImage: "app.dashed",
                                   description: Text("Choisis une app dans la liste pour voir ce qu'elle occupe et où l'envoyer."))
                .navigationTitle("MacintoshHDisTooSmall")
        }
    }

    @ViewBuilder
    private func header(_ row: AppRow) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AppIconView(path: row.iconPath, side: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.title2.weight(.semibold))
                if let version = row.app?.version {
                    Text("Version \(version)").foregroundStyle(.secondary)
                }
                if let bundleID = row.bundleID {
                    Text(bundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(FileSize.format(row.size ?? 0))
                    .font(.title3.monospacedDigit().weight(.medium))
                Text(row.isRelocated ? "déplacés" : "occupés")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Not yet moved

private struct MoveSection: View {
    @Bindable var state: AppState
    let row: AppRow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.destinationPath.isEmpty ? "Aucune destination choisie" : PathFormat.short(state.destinationPath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(state.createAppSymlink
                             ? "Un lien symbolique restera dans /Applications."
                             : "Rien ne restera dans /Applications.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Modifier…") { state.showSettings = true }
                }
                .padding(4)
            } label: {
                Label("Destination", systemImage: "arrow.right.circle")
            }

            GroupBox {
                if state.isLoadingSupport {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Recherche des caches et configurations…").foregroundStyle(.secondary)
                    }
                    .padding(6)
                } else if state.supportItems.isEmpty {
                    Text("Aucun cache ni fichier de configuration trouvé pour cette app.")
                        .foregroundStyle(.secondary)
                        .padding(6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(state.supportItems) { item in
                            SupportItemRow(item: item,
                                           isSelected: state.selectedSupportIDs.contains(item.id)) {
                                state.toggleSupportItem(item)
                            }
                            if item.id != state.supportItems.last?.id { Divider() }
                        }
                    }
                }
            } label: {
                Label("Fichiers annexes", systemImage: "tray.full")
            }

            Text("Les préférences (~/Library/Preferences) ne sont volontairement jamais déplacées : macOS les réécrit et détruirait le lien symbolique.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("À libérer : \(FileSize.format((row.size ?? 0) + state.selectedSupportBytes))")
                        .font(.headline)
                    Text("bundle + \(state.selectedSupportIDs.count) élément(s) annexe(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    state.relocateSelected()
                } label: {
                    Label("Déplacer", systemImage: "arrow.right.doc.on.clipboard")
                        .frame(minWidth: 90)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(state.destinationPath.isEmpty || state.isBusy)
            }
        }
    }
}

private struct SupportItemRow: View {
    let item: SupportItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Image(systemName: item.kind.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.kind.displayName)
                    Text(PathFormat.short(item.url.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(FileSize.format(item.size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Already moved

private struct RelocatedSection: View {
    @Bindable var state: AppState
    let record: MoveRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PathFormat.short(record.destinationRoot))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("Déplacée le \(record.movedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Afficher dans le Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([record.destinationRootURL])
                        }
                    }

                    if !FileManager.default.fileExists(atPath: record.destinationRoot) {
                        Label("Le dossier de destination est introuvable — le volume est-il monté ?",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(4)
            } label: {
                Label("Emplacement actuel", systemImage: "mappin.and.ellipse")
            }

            GroupBox {
                VStack(spacing: 0) {
                    ForEach(record.items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.isBundle ? "app.badge" : (item.supportKind?.symbolName ?? "doc"))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.isBundle ? "Bundle de l'application" : (item.supportKind?.displayName ?? item.kind))
                                Text(PathFormat.short(item.originalPath))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            if !item.symlinkCreated {
                                Text("sans lien")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(FileSize.format(item.bytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        if item.id != record.items.last?.id { Divider() }
                    }
                }
            } label: {
                Label("Éléments déplacés", systemImage: "list.bullet")
            }

            HStack {
                Text("Restaurer remet chaque élément à son emplacement d'origine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    state.restoreSelected()
                } label: {
                    Label("Restaurer", systemImage: "arrow.uturn.backward")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
            }
        }
    }
}

enum PathFormat {
    static func short(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
