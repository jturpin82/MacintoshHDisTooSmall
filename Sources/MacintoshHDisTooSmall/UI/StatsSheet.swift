import SwiftUI
import Charts

@MainActor
struct StatsSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVolumeID: String?

    private var volumes: [AppState.VolumeUsage] { state.relocatedByVolume }
    private var notRelocated: Int64 { state.notRelocatedBytes }
    private var relocated: Int64 { state.relocatedBytes(forVolumeID: selectedVolumeID) }
    private var total: Int64 { notRelocated + relocated }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Répartition de l'espace")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            if volumes.count > 1 {
                Picker("Volume de destination", selection: $selectedVolumeID) {
                    Text("Tous les volumes").tag(String?.none)
                    ForEach(volumes) { volume in
                        Text(volume.label).tag(String?.some(volume.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)
            }

            if total == 0 {
                ContentUnavailableView("Rien à afficher pour l'instant",
                                       systemImage: "chart.pie",
                                       description: Text("Les tailles se calculent en tâche de fond — reviens dans un instant."))
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                HStack(spacing: 32) {
                    Chart {
                        SectorMark(angle: .value("Octets", notRelocated),
                                  innerRadius: .ratio(0.62),
                                  angularInset: 1.5)
                            .foregroundStyle(Color.blue)
                            .cornerRadius(3)
                        SectorMark(angle: .value("Octets", relocated),
                                  innerRadius: .ratio(0.62),
                                  angularInset: 1.5)
                            .foregroundStyle(Color.teal)
                            .cornerRadius(3)
                    }
                    .frame(width: 200, height: 200)
                    .overlay {
                        VStack(spacing: 2) {
                            Text(FileSize.format(total))
                                .font(.headline.monospacedDigit())
                            Text("au total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        LegendRow(color: .blue, title: "Sur le disque", bytes: notRelocated, total: total)
                        LegendRow(color: .teal,
                                 title: selectedVolumeID == nil ? "Déplacées" : "Déplacées sur ce volume",
                                 bytes: relocated,
                                 total: total)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)

                if selectedVolumeID == nil, volumes.count > 1 {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Par volume de destination")
                            .font(.subheadline.weight(.medium))
                        ForEach(volumes) { volume in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(volume.label)
                                    Spacer()
                                    Text(FileSize.format(volume.bytes))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                                if let total = volume.totalCapacity {
                                    Text(volume.availableCapacity.map {
                                        "\(FileSize.format($0)) disponible sur \(FileSize.format(total))"
                                    } ?? "\(FileSize.format(total)) au total")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 540, height: volumes.count > 1 ? 460 : 340)
    }
}

private struct LegendRow: View {
    let color: Color
    let title: String
    let bytes: Int64
    let total: Int64

    private var percentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(bytes) / Double(total) * 100).rounded())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text("\(FileSize.format(bytes)) · \(percentage) %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
