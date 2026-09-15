import Foundation
import Darwin

public struct FileEntry {
    public let url: URL
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isLink: Bool
    public let isHidden: Bool
    public let size: Int64
    public let modified: Date
    public var name: String { url.lastPathComponent }
    public var canBrowse: Bool { isDirectory && !isPackage }

    public init(url: URL) throws {
        let values = try url.resourceValues(forKeys: Set(Self.keys))
        self.url = url
        isLink = values.isSymbolicLink ?? false
        isDirectory = values.isDirectory ?? false
        isPackage = values.isPackage ?? false
        isHidden = values.isHidden ?? url.lastPathComponent.hasPrefix(".")
        size = Int64(values.fileSize ?? 0)
        modified = values.contentModificationDate ?? .distantPast
    }

    public static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .isHiddenKey, .fileSizeKey, .contentModificationDateKey]
}

public enum FileProblem: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public func check() throws { if isCancelled { throw CancellationError() } }
}

public enum ConflictChoice { case skip, keepBoth, replace, cancel }

public enum Files {
    public static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 // Includes dangling symbolic links.
    }

    public static func named(_ name: String, in parent: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileProblem.message("Enter a name without / or a null character. The names “.” and “..” are not allowed.")
        }
        return parent.appendingPathComponent(name)
    }

    @discardableResult public static func create(name: String, in parent: URL, directory: Bool) throws -> URL {
        let url = try named(name, in: parent)
        if directory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } else {
            // O_EXCL prevents both overwriting and following an existing symlink.
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path]) }
            close(fd)
        }
        return url
    }

    public static func list(_ directory: URL, hidden: Bool) throws -> [FileEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: FileEntry.keys,
            options: hidden ? [] : [.skipsHiddenFiles])
        return urls.compactMap { try? FileEntry(url: $0) }
    }

    public static func sorted(_ values: [FileEntry], key: String = "name", ascending: Bool = true) -> [FileEntry] {
        values.sorted { a, b in
            if a.canBrowse != b.canBrowse { return a.canBrowse }
            if key == "size" && a.size != b.size { return ascending ? a.size < b.size : a.size > b.size }
            if key == "date" && a.modified != b.modified { return ascending ? a.modified < b.modified : a.modified > b.modified }
            let order = a.name.localizedStandardCompare(b.name)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    public static func search(in directory: URL, query: String, hidden: Bool, cancellation: Cancellation,
                              batch: ([FileEntry]) -> Void) throws -> Int {
        var unreadable = 0
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !hidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: FileEntry.keys,
            options: options, errorHandler: { _, _ in unreadable += 1; return !cancellation.isCancelled }) else {
            throw FileProblem.message("The folder could not be read for search.")
        }
        var found: [FileEntry] = []
        var lastDelivery = Date()
        for case let url as URL in enumerator {
            try cancellation.check()
            if url.lastPathComponent.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil,
               let entry = try? FileEntry(url: url) { found.append(entry) }
            if found.count >= 100 || Date().timeIntervalSince(lastDelivery) > 0.15 {
                if !found.isEmpty { batch(found); found.removeAll(keepingCapacity: true) }
                lastDelivery = Date()
            }
        }
        try cancellation.check()
        if !found.isEmpty { batch(found) }
        return unreadable
    }

    public static func availableName(for url: URL) -> URL {
        if !exists(url) { return url }
        let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let ext = directory ? "" : url.pathExtension
        let stem = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let name = "\(stem) (\(number))" + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    public static func rename(_ source: URL, to name: String) throws -> URL {
        let target = try named(name, in: source.deletingLastPathComponent())
        if source.path == target.path { return source }
        // Case-only rename on case-insensitive volumes still addresses the same inode.
        if exists(target) {
            var a = stat(), b = stat()
            guard lstat(source.path, &a) == 0, lstat(target.path, &b) == 0,
                  a.st_dev == b.st_dev, a.st_ino == b.st_ino,
                  source.lastPathComponent.lowercased() == name.lowercased() else {
                throw FileProblem.message("An item named “\(name)” already exists.")
            }
            guard Darwin.rename(source.path, target.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } else { try FileManager.default.moveItem(at: source, to: target) }
        return target
    }

    public static func topLevelSelection(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        let unique = urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
        return unique.filter { url in
            !unique.contains { parent in
                parent.path != url.path && url.path.hasPrefix(parent.path + "/") &&
                (try? FileEntry(url: parent)).map { $0.isDirectory && !$0.isLink } == true
            }
        }.sorted { $0.path < $1.path }
    }

    @discardableResult public static func transfer(_ source: URL, to directory: URL, move: Bool,
        cancellation: Cancellation, conflict: (URL) -> ConflictChoice) throws -> URL? {
        let fm = FileManager()
        let sourceEntry = try FileEntry(url: source)
        let resolvedParent = directory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
        if sourceEntry.isDirectory && !sourceEntry.isLink &&
            (resolvedParent.path == resolvedSource.path || resolvedParent.path.hasPrefix(resolvedSource.path + "/")) {
            throw FileProblem.message("A folder cannot be placed inside itself.")
        }
        var target = directory.appendingPathComponent(source.lastPathComponent)
        var replace = false
        if exists(target) {
            switch conflict(target) {
            case .skip: return nil
            case .keepBoth: target = availableName(for: target)
            case .cancel: cancellation.cancel(); throw CancellationError()
            case .replace: replace = true
            }
        }
        if target.resolvingSymlinksInPath().standardizedFileURL.path == resolvedSource.path {
            throw FileProblem.message("The source and destination are the same. Choose “Keep Both” to make a copy.")
        }
        try cancellation.check()
        let staging = directory.appendingPathComponent(".qe-copy-" + UUID().uuidString)
        let backup = directory.appendingPathComponent(".qe-backup-" + UUID().uuidString)
        var backedUp = false
        var stageContainsSource = false
        var committed = false
        defer {
            // A failed direct move must be restored, never cleaned up as a disposable copy.
            if !stageContainsSource { try? fm.removeItem(at: staging) }
        }
        var sourceStat = stat(), destStat = stat()
        let sameVolume = lstat(source.path, &sourceStat) == 0 && stat(directory.path, &destStat) == 0 && sourceStat.st_dev == destStat.st_dev
        do {
            if move && sameVolume {
                try fm.moveItem(at: source, to: staging)
                stageContainsSource = true
            } else {
                // ponytail: cancellation is checked between items; a single large file finishes copying first.
                let delegate = CopyCancellation(cancellation)
                fm.delegate = delegate
                defer { fm.delegate = nil }
                try fm.copyItem(at: source, to: staging)
            }
            try cancellation.check()
            if replace {
                try fm.moveItem(at: target, to: backup)
                backedUp = true
            }
            try fm.moveItem(at: staging, to: target)
            stageContainsSource = false
            committed = true
        } catch {
            var recovery: [String] = []
            if backedUp {
                do { try fm.moveItem(at: backup, to: target) }
                catch { recovery.append("Previous version preserved at: \(backup.path)") }
            }
            if stageContainsSource {
                do { try fm.moveItem(at: staging, to: source); stageContainsSource = false }
                catch { recovery.append("Source preserved at: \(staging.path)") }
            }
            if !recovery.isEmpty { throw FileProblem.message(error.localizedDescription + "\n" + recovery.joined(separator: "\n")) }
            throw error
        }
        if backedUp {
            do { try fm.removeItem(at: backup) }
            catch { throw FileProblem.message("Copy complete. The previous version remains at \(backup.path): \(error.localizedDescription)") }
        }
        if committed && move && !sameVolume {
            // Cancellation after commit leaves two copies; it must not remove the source.
            if cancellation.isCancelled { throw FileProblem.message("Copy complete: \(target.path). Move cancelled; the source was preserved.") }
            do { try fm.removeItem(at: source) }
            catch { throw FileProblem.message("Copy complete: \(target.path). Could not remove the source: \(error.localizedDescription)") }
        }
        return target
    }

    @discardableResult public static func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
}

private final class CopyCancellation: NSObject, FileManagerDelegate {
    let cancellation: Cancellation
    init(_ cancellation: Cancellation) { self.cancellation = cancellation }
    func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
        !cancellation.isCancelled
    }
}
