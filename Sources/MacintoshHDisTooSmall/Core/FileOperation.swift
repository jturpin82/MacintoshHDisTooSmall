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
            if Self.isSameVolume(from, to) {
                try fm.moveItem(at: from, to: to)
            } else {
                // FileManager's cross-volume move preserves ownership and
                // extended attributes, and neither survives a copy out of
                // /Applications: a user cannot chown to root, and
                // com.apple.provenance is refused even to root. None of it is
                // needed for the app to run, so copy without them.
                try Self.runTool("/bin/cp", ["-RX", from.path, to.path])
                try fm.removeItem(at: from)
            }
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
            if Self.isSameVolume(from, to) {
                return "/bin/mv -f \(Self.quote(from.path)) \(Self.quote(to.path))"
            }
            return "/bin/cp -RX \(Self.quote(from.path)) \(Self.quote(to.path))"
                + " && /bin/rm -rf \(Self.quote(from.path))"
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

    /// A rename only works inside one volume; the destination does not exist
    /// yet, so its parent answers for it.
    private static func isSameVolume(_ from: URL, _ to: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let source = try? from.resourceValues(forKeys: keys).volumeIdentifier,
              let target = try? to.deletingLastPathComponent()
                  .resourceValues(forKeys: keys).volumeIdentifier
        else { return false }
        return source.isEqual(target)
    }

    /// Runs a command line tool, turning a non-zero exit into an error that
    /// keeps the tool's own message and says whether privileges could help.
    private static func runTool(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }

        let message = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let denied = message.localizedCaseInsensitiveContains("not permitted")
            || message.localizedCaseInsensitiveContains("denied")
        throw NSError(domain: NSPOSIXErrorDomain,
                      code: denied ? Int(EPERM) : Int(EIO),
                      userInfo: [NSLocalizedDescriptionKey: message.isEmpty
                                 ? "\(executable) a échoué (code \(process.terminationStatus))"
                                 : message])
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

    /// If this operation is a move whose source is still in place while its
    /// destination exists, that destination can only be debris from the attempt
    /// that just failed: a cross-volume moveItem copies before it deletes, and
    /// leaves a partial copy behind when it gives up. Re-running `mv` against it
    /// would nest the bundle inside itself, so it has to go first.
    /// Returns a shell command when the cleanup needs privileges too.
    private func partialDestinationCleanup() -> String? {
        guard case let .move(from, to) = self else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path), fm.fileExists(atPath: to.path) else { return nil }
        try? fm.removeItem(at: to)
        guard fm.fileExists(atPath: to.path) else { return nil }
        return "/bin/rm -rf \(Self.quote(to.path))"
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

                var lines = ["set -e"]
                if let cleanup = operation.partialDestinationCleanup() {
                    lines.append(cleanup)
                }
                lines.append(contentsOf: operations[index...].map(\.shellCommand))

                do {
                    try PrivilegedRunner.run(shellScript: lines.joined(separator: "\n") + "\n")
                } catch let privilegedError {
                    // Without the first error the real cause stays invisible.
                    throw RelocationError.privilegedRetryFailed(
                        privileged: privilegedError.localizedDescription,
                        original: error.localizedDescription)
                }
                progress("Terminé", 1)
                return
            }
        }
        progress("Terminé", 1)
    }
}
