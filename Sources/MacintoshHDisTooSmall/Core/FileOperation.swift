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

    /// The existing path that must become writable by the current user for
    /// this operation to succeed, if it is the one that just failed with a
    /// permission error — `from` for a move (it has to be deleted entirely,
    /// not just written to), the item itself for the others, walking up to
    /// the nearest existing ancestor when the target doesn't exist yet (e.g.
    /// a destination folder that still needs to be created).
    private func pathNeedingOwnership() -> URL? {
        func nearestExisting(_ url: URL) -> URL? {
            let fm = FileManager.default
            var candidate = url
            while !fm.fileExists(atPath: candidate.path) {
                let parent = candidate.deletingLastPathComponent()
                guard parent.path != candidate.path else { return nil }
                candidate = parent
            }
            return candidate
        }
        switch self {
        case .move(let from, let to):
            return FileManager.default.fileExists(atPath: from.path) ? from : nearestExisting(to)
        case .makeDirectory(let url), .makeSymlink(let url, _), .removeSymlink(let url), .trash(let url):
            return nearestExisting(url)
        }
    }

    /// Group of whatever already owns `path`'s parent, so a fixed-up file
    /// keeps the convention already used at that location (e.g. `admin` for
    /// /Applications) instead of an arbitrary group nobody else there has.
    private static func matchingGroup(for path: URL) -> String? {
        let parent = path.deletingLastPathComponent()
        return (try? parent.resourceValues(forKeys: [.fileGroupOwnerAccountNameKey]))?
            .fileGroupOwnerAccountName
            ?? (try? path.resourceValues(forKeys: [.fileGroupOwnerAccountNameKey]))?
            .fileGroupOwnerAccountName
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

    /// Runs every operation in order. On a permission failure, the offending
    /// path is first handed back to the current user with one small
    /// `chown -R` — done as root, but that is all that runs as root — and the
    /// same operation is retried natively. This keeps every file the app ever
    /// touches owned by the user instead of root, which the previous
    /// approach (replaying the whole remaining batch as root) did not: a move
    /// that needed elevation left its destination copy, and the symlink back
    /// in /Applications, owned by root — invisible until the next restore or
    /// delete needed a password again for files that should never have
    /// needed one.
    ///
    /// If chown was not possible, or the retry still fails, that one
    /// operation and everything after it falls back to running as a single
    /// privileged script, as before.
    static func execute(_ operations: [FileOperation],
                        progress: (String, Double) -> Void) throws {
        let total = Double(max(operations.count, 1))
        var chownedPaths = Set<String>()

        var index = 0
        while index < operations.count {
            let operation = operations[index]
            progress(operation.progressLabel, Double(index) / total)
            do {
                try operation.runNative()
                index += 1
            } catch {
                guard isPermissionError(error) else { throw error }

                if let path = operation.pathNeedingOwnership(),
                   !chownedPaths.contains(path.path),
                   let group = matchingGroup(for: path) {
                    chownedPaths.insert(path.path)
                    progress("Correction des droits sur \(path.lastPathComponent)…", Double(index) / total)
                    let owner = quote("\(NSUserName()):\(group)")
                    let chown = "set -e\n/usr/sbin/chown -R \(owner) \(quote(path.path))\n"
                    do {
                        try PrivilegedRunner.run(shellScript: chown)
                        // A cross-volume move fails on its removeItem step,
                        // after cp -RX already succeeded: from still exists,
                        // which is what earned this path, but so does to.
                        // Retrying runNative() as-is would cp into that
                        // existing destination and nest the bundle inside
                        // itself, so clear it first — same debris the old
                        // fallback below also has to account for.
                        _ = operation.partialDestinationCleanup()
                        continue // retry the same operation, natively this time
                    } catch {
                        // Fall through to the old whole-batch escalation below.
                    }
                }

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
