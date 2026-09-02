import Foundation

enum PrivilegedError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Authentification annulée. Aucune modification supplémentaire n'a été effectuée."
        case .failed(let message):
            return "L'opération privilégiée a échoué : \(message)"
        }
    }
}

/// Runs a shell script as root after a standard macOS authentication prompt.
/// Uses `osascript` in a child process so it can be awaited off the main thread.
enum PrivilegedRunner {
    static func run(shellScript: String) throws {
        let fm = FileManager.default
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mhdits-\(UUID().uuidString).sh")

        try shellScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? fm.removeItem(at: scriptURL) }

        let escapedPath = scriptURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        do shell script "/bin/sh " & quoted form of "\(escapedPath)" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw PrivilegedError.failed(error.localizedDescription)
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if message.contains("-128") || message.localizedCaseInsensitiveContains("User canceled") {
                throw PrivilegedError.cancelled
            }
            throw PrivilegedError.failed(message.isEmpty ? "code \(process.terminationStatus)" : message)
        }
    }
}
