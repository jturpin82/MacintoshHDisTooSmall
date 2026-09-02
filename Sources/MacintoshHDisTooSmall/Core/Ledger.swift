import Foundation

/// Persistent list of relocations, used to move everything back exactly where it was.
final class Ledger {
    private(set) var records: [MoveRecord] = []
    private let fileURL: URL

    init() {
        let base = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacintoshHDisTooSmall")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("ledger.json")
        load()
    }

    func record(forAppNamed name: String) -> MoveRecord? {
        records.first { $0.appName == name }
    }

    func add(_ record: MoveRecord) {
        records.removeAll { $0.appName == record.appName }
        records.append(record)
        save()
    }

    func remove(appNamed name: String) {
        records.removeAll { $0.appName == name }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([MoveRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
