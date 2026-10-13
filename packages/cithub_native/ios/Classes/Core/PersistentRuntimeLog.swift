import Foundation

/// Complete local diagnostics retained for a rolling 24 hours, without redaction.
public actor PersistentRuntimeLog: RuntimeLogger {
    public static let shared = PersistentRuntimeLog()
    private let directory: URL
    private var writeError: Error?
    private var migratedLegacy = false
    private let legacyURL: URL?
    private let now: @Sendable () -> Date
    private var lastPrune: Date?
    private static let retention: TimeInterval = 24 * 60 * 60

    public init(directory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base.appendingPathComponent("cithub-logs", isDirectory: true)
        self.legacyURL = directory == nil ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("cithub-runtime.log") : nil
    }

    public func append(source: String, message: String) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !migratedLegacy {
                migratedLegacy = true
                if let legacy = legacyURL {
                    let target = directory.appendingPathComponent("legacy-runtime.log")
                    if FileManager.default.fileExists(atPath: legacy.path), !FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.copyItem(at: legacy, to: target)
                    }
                }
            }
            if lastPrune == nil || now().timeIntervalSince(lastPrune!) >= 60 {
                try prune()
            }
            let url = directory.appendingPathComponent("runtime.log")
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                    throw CithubNativeError.requestFailed("无法创建日志文件")
                }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let timestampFormatter = ISO8601DateFormatter()
            timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = timestampFormatter.string(from: now())
            try handle.write(contentsOf: Data("[\(timestamp)] [\(source)] \(message)\n".utf8))
            try handle.synchronize()
        } catch {
            writeError = error
            NSLog("Cithub log persistence failed: %@", String(describing: error))
        }
    }

    public func export() async throws -> String {
        await append(source: "runtime", message: "Exporting all retained logs as ZIP; redaction=false")
        if let writeError { throw writeError }
        try prune()
        try pruneExports()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("cithub-logs-\(UUID().uuidString).zip")
        try StoredZip.write(files: files, to: target)
        return target.path
    }

    /// Legacy multiline entries are kept with their timestamped first line.
    /// Untimestamped historical files use their modification time during migration.
    private func prune() throws {
        let cutoff = now().addingTimeInterval(-Self.retention)
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            var keep = (values.contentModificationDate ?? .distantPast) >= cutoff
            var retained = ""
            for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast(text.hasSuffix("\n") ? 1 : 0) {
                if line.hasPrefix("["), let end = line.firstIndex(of: "]"),
                   let date = fractionalFormatter.date(from: String(line[line.index(after: line.startIndex)..<end]))
                    ?? formatter.date(from: String(line[line.index(after: line.startIndex)..<end])) {
                    keep = date >= cutoff
                }
                if keep { retained += line + "\n" }
            }
            if retained.isEmpty {
                try FileManager.default.removeItem(at: url)
            } else if retained != text && retained != text + "\n" {
                try Data(retained.utf8).write(to: url, options: .atomic)
            }
        }
        lastPrune = now()
    }

    private func pruneExports() throws {
        let cutoff = now().addingTimeInterval(-Self.retention)
        for url in try FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            guard url.lastPathComponent.hasPrefix("cithub-logs-"), url.pathExtension == "zip" else { continue }
            if (try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) < cutoff {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    public func clear() throws {
        if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
            try FileManager.default.removeItem(at: legacyURL)
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        writeError = nil
        lastPrune = nil
    }
}

/// Streaming ZIP64 with stored entries; keeps arbitrary binary log bytes intact.
public enum StoredZip {
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        return crc
    }
    public static func write(files: [URL], to target: URL) throws {
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw CithubNativeError.requestFailed("无法创建日志 ZIP")
        }
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        do {
            var central = Data()
            for url in files {
                let offset = try output.offset()
                let name = Data(url.lastPathComponent.utf8)
                guard name.count <= Int(UInt16.max) else { throw CithubNativeError.invalidInput("日志文件名过长") }
                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                let size = try input.seekToEnd()
                try input.seek(toOffset: 0)
                var local = Data()
                local.put(UInt32(0x04034b50)); local.put(UInt16(45)); local.put(UInt16(0x0808))
                local.put(UInt16(0)); local.put(UInt16(0)); local.put(UInt16(0))
                local.put(UInt32(0)); local.put(UInt32.max); local.put(UInt32.max)
                local.put(UInt16(name.count)); local.put(UInt16(20)); local.append(name)
                local.put(UInt16(1)); local.put(UInt16(16)); local.put(size); local.put(size)
                try output.write(contentsOf: local)
                var crc = UInt32.max
                var written: UInt64 = 0
                while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    for byte in chunk {
                        crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)]
                    }
                    try output.write(contentsOf: chunk)
                    written += UInt64(chunk.count)
                }
                guard written == size else { throw CithubNativeError.requestFailed("日志在导出过程中发生变化，请重试") }
                crc ^= UInt32.max
                var descriptor = Data()
                descriptor.put(UInt32(0x08074b50)); descriptor.put(crc); descriptor.put(size); descriptor.put(size)
                try output.write(contentsOf: descriptor)
                central.put(UInt32(0x02014b50)); central.put(UInt16(45)); central.put(UInt16(45))
                central.put(UInt16(0x0808)); central.put(UInt16(0)); central.put(UInt16(0)); central.put(UInt16(0))
                central.put(crc); central.put(UInt32.max); central.put(UInt32.max)
                central.put(UInt16(name.count)); central.put(UInt16(28)); central.put(UInt16(0))
                central.put(UInt16(0)); central.put(UInt16(0)); central.put(UInt32(0)); central.put(UInt32.max)
                central.append(name); central.put(UInt16(1)); central.put(UInt16(24))
                central.put(size); central.put(size); central.put(offset)
            }
            let centralOffset = try output.offset()
            try output.write(contentsOf: central)
            let zip64Offset = try output.offset()
            var footer = Data()
            footer.put(UInt32(0x06064b50)); footer.put(UInt64(44)); footer.put(UInt16(45)); footer.put(UInt16(45))
            footer.put(UInt32(0)); footer.put(UInt32(0)); footer.put(UInt64(files.count)); footer.put(UInt64(files.count))
            footer.put(UInt64(central.count)); footer.put(centralOffset)
            footer.put(UInt32(0x07064b50)); footer.put(UInt32(0)); footer.put(zip64Offset); footer.put(UInt32(1))
            footer.put(UInt32(0x06054b50)); footer.put(UInt16(0)); footer.put(UInt16(0))
            footer.put(UInt16.max); footer.put(UInt16.max); footer.put(UInt32.max); footer.put(UInt32.max); footer.put(UInt16(0))
            try output.write(contentsOf: footer)
            try output.synchronize()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }
}

private extension Data {
    mutating func put<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
