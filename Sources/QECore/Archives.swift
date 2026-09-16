import Foundation
import Darwin

public enum Archives {
    private static func run(_ arguments: [String], cancellation: Cancellation, report: (String) -> Void) throws {
        try cancellation.check()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe
        // Drain stderr while tar runs, retaining only a bounded error message.
        let lock = NSLock()
        var diagnostics = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock(); defer { lock.unlock() }
            if diagnostics.count < 32_768 { diagnostics.append(data.prefix(32_768 - diagnostics.count)) }
        }
        defer { pipe.fileHandleForReading.readabilityHandler = nil }
        try runProcess(process, cancellation: cancellation, report: report)
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        diagnostics.append(remainder.prefix(max(0, 32_768 - diagnostics.count)))
        let message = String(decoding: diagnostics, as: UTF8.self)
        lock.unlock()
        try cancellation.check()
        guard process.terminationStatus == 0 else {
            throw FileProblem.message("The archive operation failed. The archive may be corrupt, password-protected, or inaccessible.\n" + message)
        }
    }

    package static func runProcess(_ process: Process, cancellation: Cancellation, report: (String) -> Void = { _ in },
                                   forceKill: (pid_t) -> Void = { _ = Darwin.kill($0, SIGKILL) }) throws {
        try cancellation.check()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        defer { process.terminationHandler = nil; cancellation.setPendingMessage(nil) }
        try process.run()
        while finished.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            guard cancellation.isCancelled else { continue }
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + .seconds(2)) == .timedOut {
                if process.isRunning { forceKill(process.processIdentifier) }
                if finished.wait(timeout: .now() + .seconds(2)) == .timedOut {
                    let message = "The archiver has not stopped. Disk access may be blocked. Temporary files are being kept. Wait for the disk to respond, or let other operations finish before using macOS Force Quit."
                    cancellation.setPendingMessage(message)
                    report(message)
                    // Never return to the caller's cleanup while the process may still write.
                    finished.wait()
                }
            }
            break
        }
        try cancellation.check()
    }

    public static func create(_ sources: [URL], at destination: URL, format: String, cancellation: Cancellation,
                              report: (String) -> Void = { _ in }) throws {
        guard ["zip", "7z"].contains(format), !sources.isEmpty else { throw FileProblem.message("Select files and choose ZIP or 7z.") }
        guard !Files.exists(destination) else { throw FileProblem.message("An archive with this name already exists.") }
        let selected = try Files.topLevelSelection(sources, cancellation: cancellation)
        let parent = selected[0].deletingLastPathComponent()
        guard selected.allSatisfy({ $0.deletingLastPathComponent().path == parent.path }) else {
            throw FileProblem.message("Select items from the same folder to create an archive.")
        }
        let resolvedDestination = destination.deletingLastPathComponent().resolvingSymlinksInPath().path
        for source in selected {
            let entry = try FileEntry(url: source)
            let resolved = source.resolvingSymlinksInPath().path
            if entry.isDirectory && !entry.isLink && (resolvedDestination == resolved || resolvedDestination.hasPrefix(resolved + "/")) {
                throw FileProblem.message("Save the archive outside the folder being archived.")
            }
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".qe-archive-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        // ./ prefixes also prevent bsdtar's special @archive operand syntax.
        try run(["-c", "--format=" + (format == "7z" ? "7zip" : "zip"), "-f", temporary.path,
                 "-C", parent.path, "--"] + selected.map { "./" + $0.lastPathComponent }, cancellation: cancellation, report: report)
        try cancellation.check()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    public static func extract(_ archive: URL, to destination: URL, cancellation: Cancellation, report: (String) -> Void = { _ in }) throws {
        guard ["zip", "7z"].contains(archive.pathExtension.lowercased()) else {
            throw FileProblem.message("ZIP and 7z archives are supported.")
        }
        guard !Files.exists(destination) else { throw FileProblem.message("The destination folder already exists. Choose a different name.") }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".qe-extract-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Never add -P or -U: bsdtar rejects .. and intermediate symlink traversal by default.
        try run(["-x", "--safe-writes", "--no-same-owner", "--no-same-permissions", "-f", archive.path,
                 "-C", temporary.path], cancellation: cancellation, report: report)
        try cancellation.check()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
