import Foundation

enum FileSize {
    /// Allocated size on disk of a file or directory tree.
    /// Symlinks report 0 so an already relocated item is never counted twice.
    static func onDisk(of url: URL) -> Int64 {
        let fm = FileManager.default

        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            return 0
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }

        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: keys,
                                             options: [],
                                             errorHandler: { _, _ in true }) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
