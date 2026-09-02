import Foundation

/// A single filesystem step, executable either directly or as a shell command
/// inside a privileged script.
enum FileOperation {
    case makeDirectory(URL)
    case move(from: URL, to: URL)
    case makeSymlink(link: URL, target: URL)
    case removeSymlink(URL)
    case trash(URL)

    var progressLabel: String {
        switch self {
        case .makeDirectory(let url):
            return "Création de \(url.lastPathComponent)"
        case .move(let from, _):
            return "Déplacement de \(from.lastPathComponent)"
        case .makeSymlink(let link, _):
            return "Lien symbolique pour \(link.lastPathComponent)"
        case .removeSymlink(let url):
            return "Retrait du lien \(url.lastPathComponent)"
        case .trash(let url):
            return "Mise à la corbeille de \(url.lastPathComponent)"
        }
    }

    func runNative() throws {
        let fm = FileManager.default
        switch self {
        case .makeDirectory(let url):
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        case .move(let from, let to):
            try fm.moveItem(at: from, to: to)
        case .makeSymlink(let link, let target):
            try fm.createSymbolicLink(at: link, withDestinationURL: target)
        case .removeSymlink(let url):
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink == true else { return }
            try fm.removeItem(at: url)
        case .trash(let url):
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain && error.code == NSFeatureUnsupportedError {
                // exFAT / NTFS volumes have no Trash; say so instead of surfacing "Cocoa error 3328".
                throw RelocationError.trashUnavailable(url.path)
            }
        }
    }

    var shellCommand: String {
        switch self {
        case .makeDirectory(let url):
            return "/bin/mkdir -p \(Self.quote(url.path))"
        case .move(let from, let to):
            return "/bin/mv -f \(Self.quote(from.path)) \(Self.quote(to.path))"
        case .makeSymlink(let link, let target):
            return "/bin/ln -s \(Self.quote(target.path)) \(Self.quote(link.path))"
        case .removeSymlink(let url):
            let path = Self.quote(url.path)
            return "if [ -L \(path) ]; then /bin/rm \(path); fi"
        case .trash(let url):
            // root cannot use the Trash, so an elevated deletion is permanent.
            return "/bin/rm -rf \(Self.quote(url.path))"
        }
    }

    private static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// True when `error` means "you are not allowed", i.e. retrying as root can help.
    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionError(underlying)
        }
        return false
    }

    /// Runs every operation in order. On the first permission failure the whole
    /// remainder is re-run as a single privileged script, so the user is asked
    /// for a password at most once per operation batch.
    static func execute(_ operations: [FileOperation],
                        progress: (String, Double) -> Void) throws {
        let total = Double(max(operations.count, 1))

        for (index, operation) in operations.enumerated() {
            progress(operation.progressLabel, Double(index) / total)
            do {
                try operation.runNative()
            } catch {
                guard isPermissionError(error) else { throw error }
                progress("Authentification requise…", Double(index) / total)
                let script = (["set -e"] + operations[index...].map(\.shellCommand))
                    .joined(separator: "\n") + "\n"
                try PrivilegedRunner.run(shellScript: script)
                progress("Terminé", 1)
                return
            }
        }
        progress("Terminé", 1)
    }
}
