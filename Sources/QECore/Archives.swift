import Foundation
import Darwin

public enum Archives {
    // Re-exec before AppKit starts so tar cannot read from a terminal that launched QE.
    // The password travels only over stdin, never through arguments or the environment.
    public static func runWorkerIfRequested() {
        guard CommandLine.arguments.dropFirst().first == "--qe-archive-worker" else { return }
        let tty = open("/dev/tty", O_RDWR)
        if tty >= 0 {
            guard ioctl(tty, TIOCNOTTY) == 0 else { exit(1) }
            close(tty)
        }
        let arguments = ["/usr/bin/tar"] + CommandLine.arguments.dropFirst(2)
        let pointers = arguments.map { strdup($0) } + [nil]
        pointers.withUnsafeBufferPointer { _ = execv("/usr/bin/tar", $0.baseAddress!) }
        exit(1)
    }

    private static func run(_ arguments: [String], cancellation: Cancellation, report: (String) -> Void,
                            password: ((Bool) throws -> String?)? = nil) throws {
        try cancellation.check()
        let process = Process()
        process.executableURL = password == nil ? URL(fileURLWithPath: "/usr/bin/tar") : Bundle.main.executableURL
        process.arguments = password == nil ? arguments : ["--qe-archive-worker"] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C" // Keep the passphrase prompt stable.
        process.environment = environment
        let input = Pipe()
        process.standardInput = password == nil ? FileHandle.nullDevice : input
        defer { try? input.fileHandleForWriting.close() }
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe
        // Drain stderr while tar runs, retaining only a bounded error message.
        let lock = NSLock()
        var diagnostics = Data()
        let prompt = Data("Enter passphrase:".utf8)
        var pending = Data(), requests = 0
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock(); defer { lock.unlock() }
            if diagnostics.count < 32_768 { diagnostics.append(data.prefix(32_768 - diagnostics.count)) }
            if password != nil {
                pending.append(data)
                while let range = pending.range(of: prompt) {
                    requests += 1
                    pending.removeSubrange(pending.startIndex..<range.upperBound)
                }
                pending = Data(pending.suffix(prompt.count - 1))
            }
        }
        defer { pipe.fileHandleForReading.readabilityHandler = nil }
        var attempts = 0, inputError: Error?
        do {
            try runProcess(process, cancellation: cancellation, report: report, poll: {
                lock.lock()
                let requested = requests > attempts
                lock.unlock()
                guard requested, let password, !cancellation.isCancelled else { return }
                do {
                    guard let value = try password(attempts > 0) else { throw CancellationError() }
                    try cancellation.check()
                    // bsdtar reads a single line into a 1024-byte buffer.
                    guard value.utf8.count < 1024, !value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) else {
                        throw FileProblem.message("The password must be shorter than 1024 bytes and contain no line breaks or null characters.")
                    }
                    attempts += 1
                    try input.fileHandleForWriting.write(contentsOf: Data((value + "\n").utf8))
                } catch {
                    inputError = error
                    cancellation.cancel()
                }
            })
        } catch {
            throw inputError ?? error
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        diagnostics.append(remainder.prefix(max(0, 32_768 - diagnostics.count)))
        let message = String(decoding: diagnostics, as: UTF8.self)
        lock.unlock()
        try cancellation.check()
        guard process.terminationStatus == 0 else {
            throw FileProblem.message("The archive operation failed. The archive may be corrupt, use unsupported encryption, or be inaccessible.\n" + message)
        }
    }

    package static func runProcess(_ process: Process, cancellation: Cancellation, report: (String) -> Void = { _ in },
                                   forceKill: (pid_t) -> Void = { _ = Darwin.kill($0, SIGKILL) }, poll: () -> Void = {}) throws {
        try cancellation.check()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        defer { process.terminationHandler = nil; cancellation.setPendingMessage(nil) }
        try process.run()
        while finished.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            poll()
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

    public static func extract(_ archive: URL, to destination: URL, cancellation: Cancellation, report: (String) -> Void = { _ in },
                               password: @escaping (Bool) throws -> String? = { _ in throw FileProblem.message("This archive requires a password.") }) throws {
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
                 "-C", temporary.path], cancellation: cancellation, report: report, password: password)
        try cancellation.check()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
