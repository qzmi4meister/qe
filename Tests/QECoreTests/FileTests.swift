import Foundation
import QECore

final class FileTests {
    var root: URL!
    func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("qe-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func folder(_ name: String) throws -> URL { try Files.create(name: name, in: root, directory: true) }
    func file(_ name: String, in parent: URL? = nil, data: Data = Data("original".utf8)) throws -> URL {
        let url = try Files.create(name: name, in: parent ?? root, directory: false)
        try data.write(to: url); return url
    }

    func testCreateRenameHiddenAndNoOverwrite() throws {
        let url = try file(".test file")
        expectError(try Files.create(name: url.lastPathComponent, in: root, directory: false))
        expectEqual(try Data(contentsOf: url), Data("original".utf8))
        expectEqual(try Files.list(root, hidden: false).count, 0)
        expectEqual(try Files.list(root, hidden: true).count, 1)
        let renamed = try Files.rename(url, to: "LICENSE")
        expectFalse(Files.exists(url)); expectTrue(Files.exists(renamed))
        for invalid in ["", ".", "..", "a/b", "a\0b"] {
            expectError(try Files.create(name: invalid, in: root, directory: false))
        }
        let empty = try Files.create(name: "no extension", in: root, directory: false)
        expectEqual(try Data(contentsOf: empty).count, 0)
    }

    func testDanglingLinkIsNotOverwritten() throws {
        let link = root.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("missing"))
        expectTrue(Files.exists(link))
        expectError(try Files.create(name: "dangling", in: root, directory: false))
        expectFalse(Files.exists(root.appendingPathComponent("missing")))
    }

    func testTransferConflictsAndSourcePreservation() throws {
        let source = try file("item.txt")
        let destination = try folder("destination")
        let existing = try file("item.txt", in: destination, data: Data("old".utf8))
        let token = Cancellation()
        expectNil(try Files.transfer(source, to: destination, move: false, cancellation: token) { _ in .skip })
        expectEqual(try Data(contentsOf: existing), Data("old".utf8))
        let both = try unwrap(Files.transfer(source, to: destination, move: false, cancellation: token) { _ in .keepBoth })
        expectEqual(both.lastPathComponent, "item (2).txt")
        expectEqual(try Data(contentsOf: both), Data("original".utf8))
        try Files.transfer(source, to: destination, move: true, cancellation: token) { _ in .replace }
        expectFalse(Files.exists(source)); expectEqual(try Data(contentsOf: existing), Data("original".utf8))
        expectFalse(try Files.list(destination, hidden: true).contains { $0.name.hasPrefix(".qe-") })
    }

    func testCancellationDoesNotLoseSourceOrDestination() throws {
        let source = try file("item")
        let destination = try folder("destination")
        let existing = try file("item", in: destination, data: Data("old".utf8))
        let token = Cancellation()
        expectError(try Files.transfer(source, to: destination, move: true, cancellation: token) { _ in token.cancel(); return .replace })
        expectEqual(try Data(contentsOf: source), Data("original".utf8))
        expectEqual(try Data(contentsOf: existing), Data("old".utf8))
    }

    func testFailedReplacementRestoresMovedSource() throws {
        let source = try file("item")
        let destination = try folder("destination")
        let existing = try file("item", in: destination)
        expectError(try Files.transfer(source, to: destination, move: true, cancellation: Cancellation()) { _ in
            // Simulate another application removing the destination after the conflict dialog.
            try? FileManager.default.removeItem(at: existing)
            return .replace
        })
        expectEqual(try Data(contentsOf: source), Data("original".utf8))
        expectFalse(try Files.list(destination, hidden: true).contains { $0.name.hasPrefix(".qe-") })
    }

    func testTrash() throws {
        let source = try file("qe-trash-check-" + UUID().uuidString)
        let destination = try unwrap(Files.trash(source))
        defer { try? FileManager.default.removeItem(at: destination) }
        expectFalse(Files.exists(source))
        expectEqual(try Data(contentsOf: destination), Data("original".utf8))
    }

    func testFileAssociations() throws {
        let suite = "local.qe.association-check-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let associations = FileAssociations(preferences: preferences)
        let upper = root.appendingPathComponent("Report.TXT")
        let lower = root.appendingPathComponent("notes.txt")
        let markdown = root.appendingPathComponent("notes.md")
        let app = URL(fileURLWithPath: "/Applications/Example.app")
        associations.remember(app, bundleIdentifier: "example.editor", for: upper)
        let reloaded = FileAssociations(preferences: UserDefaults(suiteName: suite)!)
        expectEqual(reloaded.application(for: lower)?.url.path, app.path)
        expectEqual(reloaded.application(for: lower)?.bundleIdentifier, "example.editor")
        expectNil(reloaded.application(for: markdown))
        for name in ["LICENSE", ".gitignore", "trailing."] {
            let file = root.appendingPathComponent(name)
            expectNil(FileAssociations.fileExtension(for: file))
            associations.remember(app, bundleIdentifier: nil, for: file)
            expectNil(associations.application(for: file))
        }
        expectNil(FileAssociations.fileExtension(for: URL(string: "https://example.com/file.txt")!))
        let replacement = URL(fileURLWithPath: "/Applications/Other.app")
        associations.remember(replacement, bundleIdentifier: nil, for: lower)
        expectEqual(reloaded.application(for: upper)?.url.path, replacement.path)
        expectNil(reloaded.application(for: upper)?.bundleIdentifier)
        associations.remember(app, bundleIdentifier: nil, for: markdown)
        reloaded.reset(for: upper)
        expectNil(associations.application(for: lower))
        expectEqual(associations.application(for: markdown)?.url.path, app.path)
    }

    func testDirectorySelfCopyAndLinks() throws {
        let directory = try folder("source")
        let child = try Files.create(name: "child", in: directory, directory: true)
        expectError(try Files.transfer(directory, to: child, move: false, cancellation: Cancellation()) { _ in .replace })
        let link = root.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        expectError(try Files.transfer(directory, to: link, move: false, cancellation: Cancellation()) { _ in .replace })
        let dest = try folder("dest")
        let copied = try unwrap(Files.transfer(link, to: dest, move: false, cancellation: Cancellation()) { _ in .replace })
        expectTrue(try FileEntry(url: copied).isLink)
        expectEqual(try Files.topLevelSelection([directory, child, directory]), [directory])
    }

    func testTopLevelSelection() throws {
        let directory = try folder("foo")
        let sibling = try folder("foobar")
        let nested = try Files.create(name: "nested", in: directory, directory: true)
        let child = try file("child.txt", in: nested)
        let siblingChild = try file("child.txt", in: sibling)
        let plain = try file("plain.txt")
        let link = root.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let linkedChild = link.appendingPathComponent("nested/child.txt")
        let dangling = root.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("missing"))

        expectEqual(try Files.topLevelSelection([]), [])
        expectEqual(try Files.topLevelSelection([child, siblingChild, nested, directory, directory]), [directory, siblingChild])
        expectEqual(try Files.topLevelSelection([directory, directory.appendingPathComponent("."), child]), [directory])
        let alternate = directory.appendingPathComponent(".")
        expectEqual(try Files.topLevelSelection([alternate, directory]), [alternate])
        expectEqual(try Files.topLevelSelection([plain, sibling, directory]), [directory, sibling, plain])
        expectEqual(try Files.topLevelSelection([linkedChild, link, directory, child]), [directory, link, linkedChild])
        expectEqual(try Files.topLevelSelection([dangling, dangling]), [dangling])
        // Non-directories and missing ancestors must not hide selected descendants.
        let invalidChild = plain.appendingPathComponent("child")
        let missing = root.appendingPathComponent("absent")
        expectEqual(try Files.topLevelSelection([invalidChild, plain]), [plain, invalidChild])
        expectEqual(try Files.topLevelSelection([missing.appendingPathComponent("child"), missing]), [missing, missing.appendingPathComponent("child")])
        // Preserve the existing root-selection behavior and terminate at the root.
        let filesystemRoot = URL(fileURLWithPath: "/")
        expectEqual(try Files.topLevelSelection([directory, filesystemRoot, filesystemRoot]), [filesystemRoot, directory])
        let cancelled = Cancellation(); cancelled.cancel()
        do {
            _ = try Files.topLevelSelection([directory, child], cancellation: cancelled)
            expectTrue(false, "Cancelled selection must throw CancellationError")
        } catch is CancellationError {} // Cancellation must not return a partial selection.
    }

    func testSearchNamesHiddenAndNoLinkCycles() throws {
        let directory = try folder("nested")
        _ = try file("Needle.txt", in: directory)
        _ = try file(".needle", in: directory)
        _ = try file("other", in: directory, data: Data("needle".utf8))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("cycle"), withDestinationURL: root)
        var found: [FileEntry] = []
        let unreadable = try Files.search(in: root, query: "needle", hidden: false, cancellation: Cancellation()) { found += $0 }
        expectEqual(unreadable, 0); expectEqual(found.map(\.name), ["Needle.txt"])
        found = []
        _ = try Files.search(in: root, query: "needle", hidden: true, cancellation: Cancellation()) { found += $0 }
        expectEqual(Set(found.map(\.name)), Set(["Needle.txt", ".needle"]))
    }

    func testSearchScope() throws {
        let current = try folder("current")
        let nested = try Files.create(name: "needle-folder", in: current, directory: true)
        _ = try file("needle-outside.txt")
        _ = try file("needle-direct.txt", in: current)
        _ = try file(".needle-hidden", in: current)
        _ = try file("needle-nested.txt", in: nested)
        var found: [FileEntry] = []
        _ = try Files.search(in: current, query: "NEEDLE", hidden: false, recursive: false, cancellation: Cancellation()) { found += $0 }
        expectEqual(Set(found.map(\.name)), Set(["needle-direct.txt", "needle-folder"]))
        found = []
        _ = try Files.search(in: current, query: "needle", hidden: true, recursive: false, cancellation: Cancellation()) { found += $0 }
        expectEqual(Set(found.map(\.name)), Set(["needle-direct.txt", "needle-folder", ".needle-hidden"]))
        found = []
        _ = try Files.search(in: current, query: "needle", hidden: false, recursive: true, cancellation: Cancellation()) { found += $0 }
        expectEqual(Set(found.map(\.name)), Set(["needle-direct.txt", "needle-folder", "needle-nested.txt"]))
        let cancelled = Cancellation(); cancelled.cancel()
        expectError(try Files.search(in: current, query: "needle", hidden: true, recursive: false, cancellation: cancelled) { _ in })
    }

    func testArchiveRoundTripAndLiteralNames() throws {
        let source = try folder("source")
        let names = ["café with spaces.txt", ".hidden", "-option", "@archive", "line\nbreak", "empty"]
        let urls = try names.map { try file($0, in: source, data: $0 == "empty" ? Data() : Data($0.utf8)) }
        for format in ["zip", "7z"] {
            let archive = root.appendingPathComponent("test." + format)
            try Archives.create(urls, at: archive, format: format, cancellation: Cancellation())
            let output = root.appendingPathComponent("output-" + format)
            try Archives.extract(archive, to: output, cancellation: Cancellation())
            for url in urls { expectEqual(try Data(contentsOf: url), try Data(contentsOf: output.appendingPathComponent(url.lastPathComponent))) }
            expectError(try Archives.create(urls, at: archive, format: format, cancellation: Cancellation()))
            expectError(try Archives.extract(archive, to: output, cancellation: Cancellation()))
        }
    }

    func testArchiveDestinationInsideSourceRejected() throws {
        let source = try folder("source")
        expectError(try Archives.create([source], at: source.appendingPathComponent("loop.zip"), format: "zip", cancellation: Cancellation()))
    }

    func testCorruptAndCancelledArchivesLeaveNoOutput() throws {
        let corrupt = try file("bad.zip")
        let output = root.appendingPathComponent("output")
        expectError(try Archives.extract(corrupt, to: output, cancellation: Cancellation()))
        expectFalse(Files.exists(output))
        let cancelled = Cancellation(); cancelled.cancel()
        let archive = root.appendingPathComponent("cancelled.zip")
        expectError(try Archives.create([corrupt], at: archive, format: "zip", cancellation: cancelled))
        expectFalse(Files.exists(archive))
        expectFalse(try Files.list(root, hidden: true).contains { $0.name.hasPrefix(".qe-") })
    }

    func testUntrustedArchiveCannotEscapeExtractionFolder() throws {
        // Fixtures are generated independently of our archive writer.
        let script = """
        import sys, zipfile, stat
        from pathlib import Path
        root = Path(sys.argv[1])
        with zipfile.ZipFile(root / 'traversal.zip', 'w') as z:
            z.writestr('../escaped', 'bad')
        with zipfile.ZipFile(root / 'symlink.zip', 'w') as z:
            info = zipfile.ZipInfo('link')
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(info, str(root))
            z.writestr('link/escaped', 'bad')
        with zipfile.ZipFile(root / 'absolute.zip', 'w') as z:
            z.writestr(str(root / 'escaped'), 'bad')
        """
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, root.path]; try process.run(); process.waitUntilExit()
        expectEqual(process.terminationStatus, 0)
        for name in ["traversal", "symlink", "absolute"] {
            let destination = root.appendingPathComponent(name)
            do { try Archives.extract(root.appendingPathComponent(name + ".zip"), to: destination, cancellation: Cancellation()) }
            catch { expectFalse(Files.exists(destination)) }
            expectFalse(Files.exists(root.appendingPathComponent("escaped")), name)
        }
    }

    func checkVolume(_ volume: URL) throws {
        let destination = volume.appendingPathComponent("qe-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: destination) }
        let source = try file("move-across-disks.txt")
        let moved = try unwrap(Files.transfer(source, to: destination, move: true, cancellation: Cancellation()) { _ in .replace })
        expectFalse(Files.exists(source)); expectEqual(try Data(contentsOf: moved), Data("original".utf8))

        let large = try file("too-large.bin", data: Data())
        let handle = try FileHandle(forWritingTo: large)
        let block = Data(repeating: 0xa5, count: 1024 * 1024)
        for _ in 0..<48 { try handle.write(contentsOf: block) }
        try handle.close()
        let existing = try file("too-large.bin", in: destination, data: Data("keep me".utf8))
        // The dedicated test image is 32 MiB: copying 48 MiB must fail before replacement.
        expectError(try Files.transfer(large, to: destination, move: true, cancellation: Cancellation()) { _ in .replace })
        expectTrue(Files.exists(large)); expectEqual(try Data(contentsOf: existing), Data("keep me".utf8))
        expectFalse(try Files.list(destination, hidden: true).contains { $0.name.hasPrefix(".qe-") })
    }

    func benchmark() throws {
        for index in 0..<10_000 { _ = try Files.create(name: "file-\(index).txt", in: root, directory: false) }
        let started = Date()
        let entries = Files.sorted(try Files.list(root, hidden: true))
        expectEqual(entries.count, 10_000)
        expectEqual(entries[2].name, "file-2.txt")
        print(String(format: "10,000 entries: read metadata + sort = %.3f s", Date().timeIntervalSince(started)))
        for count in [500, 1_000, 2_000, 10_000] {
            let urls = Array(entries.prefix(count).map(\.url).reversed())
            let expected = urls.sorted { $0.path < $1.path }
            let selectionStarted = Date()
            let selection = try Files.topLevelSelection(urls)
            let elapsed = Date().timeIntervalSince(selectionStarted)
            expectEqual(selection, expected)
            print(String(format: "%d entries: top-level selection = %.3f s", count, elapsed))
        }
    }
}


private var failures = 0
private func failure(_ message: String, _ line: UInt) {
    failures += 1
    print("FAIL line \(line): \(message)")
}
func expectEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, line: UInt = #line) {
    do { if try a() != b() { failure("Values differ", line) } } catch { failure(error.localizedDescription, line) }
}
func expectTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "Expected true", line: UInt = #line) {
    do { if try !value() { failure(message, line) } } catch { failure(error.localizedDescription, line) }
}
func expectFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "Expected false", line: UInt = #line) {
    do { if try value() { failure(message, line) } } catch { failure(error.localizedDescription, line) }
}
func expectNil<T>(_ value: @autoclosure () throws -> T?, line: UInt = #line) {
    do { if try value() != nil { failure("Expected nil", line) } } catch { failure(error.localizedDescription, line) }
}
func expectError<T>(_ value: @autoclosure () throws -> T, line: UInt = #line) {
    do { _ = try value(); failure("Expected an error", line) } catch {}
}
func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw FileProblem.message("Expected a value") }; return value
}

@main struct CoreChecks {
    static func main() throws {
        let tests = FileTests()
        let cases: [(String, () throws -> Void)] = [
            ("create, rename, hidden and no overwrite", tests.testCreateRenameHiddenAndNoOverwrite),
            ("dangling symlink", tests.testDanglingLinkIsNotOverwritten),
            ("transfer and conflicts", tests.testTransferConflictsAndSourcePreservation),
            ("cancelled transfer", tests.testCancellationDoesNotLoseSourceOrDestination),
            ("rollback after failed replacement", tests.testFailedReplacementRestoresMovedSource),
            ("trash", tests.testTrash),
            ("extension associations, persistence and reset", tests.testFileAssociations),
            ("directory self-copy and symlinks", tests.testDirectorySelfCopyAndLinks),
            ("top-level selection, duplicates and symlinks", tests.testTopLevelSelection),
            ("recursive name search", tests.testSearchNamesHiddenAndNoLinkCycles),
            ("search scope, hidden files and cancellation", tests.testSearchScope),
            ("ZIP/7z round trips", tests.testArchiveRoundTripAndLiteralNames),
            ("archive destination validation", tests.testArchiveDestinationInsideSourceRejected),
            ("corrupt and cancelled archives", tests.testCorruptAndCancelledArchivesLeaveNoOutput),
            ("untrusted archive paths", tests.testUntrustedArchiveCannotEscapeExtractionFolder)
        ]
        for (name, test) in cases {
            let before = failures
            try tests.setUpWithError()
            do { try test() } catch { failure(error.localizedDescription, #line) }
            try tests.tearDownWithError()
            print("\(failures == before ? "PASS" : "FAIL") \(name)")
        }
        if let index = CommandLine.arguments.firstIndex(of: "--volume"), CommandLine.arguments.indices.contains(index + 1) {
            try tests.setUpWithError()
            do { try tests.checkVolume(URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { failure(error.localizedDescription, #line) }
            try tests.tearDownWithError()
            print("Cross-volume transfer and disk-full checks completed")
        }
        if CommandLine.arguments.contains("--benchmark") {
            try tests.setUpWithError(); try tests.benchmark(); try tests.tearDownWithError()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--readonly-volume"), CommandLine.arguments.indices.contains(index + 1) {
            try tests.setUpWithError()
            let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let source = try tests.file("readonly-test")
            expectError(try Files.create(name: "qe-readonly-test", in: destination, directory: false))
            expectError(try Files.transfer(source, to: destination, move: true, cancellation: Cancellation()) { _ in .skip })
            expectTrue(Files.exists(source))
            try tests.tearDownWithError()
            print("Read-only volume checks completed")
        }
        print("\(cases.count) scenarios, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
