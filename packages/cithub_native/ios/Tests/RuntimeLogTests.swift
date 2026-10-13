import Foundation
import Testing
@testable import CithubNativeCore

@Suite("Complete local log export")
struct RuntimeLogTests {
    @Test("Logs survive restart, retain raw contents and export an interoperable ZIP64")
    func persistentZIP() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = PersistentRuntimeLog(directory: directory)
        let original = "password=原始密码 Cookie=SESSION=secret\n" + String(repeating: "完整日志\n", count: 2100)
        await first.append(source: "test", message: original)
        let legacy = directory.appendingPathComponent("runtime.log.1")
        try Data("历史日志 cookie=old".utf8).write(to: legacy)
        let second = PersistentRuntimeLog(directory: directory)
        await second.append(source: "test", message: String(repeating: "x", count: 1100000))
        let archive = try await second.export()
        defer { try? FileManager.default.removeItem(atPath: archive) }
        #expect(archive.hasSuffix(".zip"))
        let list = try run("/usr/bin/unzip", ["-Z1", archive])
        #expect(list.contains("runtime.log.1"))
        let content = try run("/usr/bin/unzip", ["-p", archive, "runtime.log"])
        #expect(content.contains(original))
        #expect(content.contains(String(repeating: "x", count: 1100000)))
        #expect(try run("/usr/bin/unzip", ["-p", archive, "runtime.log.1"]) == "历史日志 cookie=old")
        try await second.clear()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Rolling 24 hour retention preserves boundary and multiline records across restart")
    func retention() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        let file = directory.appendingPathComponent("runtime.log")
        try Data("[2026-10-12T11:59:59Z] [test] expired\nold continuation\n[2026-10-12T12:00:00Z] [test] boundary\nraw password=密码\n[2026-10-13T11:00:00Z] [test] recent\n".utf8).write(to: file)
        let legacy = directory.appendingPathComponent("runtime.log.1")
        try Data("expired legacy".utf8).write(to: legacy)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-86401)], ofItemAtPath: legacy.path)
        let logger = PersistentRuntimeLog(directory: directory, now: { now })
        let archive = try await logger.export()
        defer { try? FileManager.default.removeItem(atPath: archive) }
        let content = try run("/usr/bin/unzip", ["-p", archive, "runtime.log"])
        #expect(!content.contains("expired"))
        #expect(!content.contains("old continuation"))
        #expect(content.contains("boundary\nraw password=密码"))
        #expect(content.contains("recent"))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("Binary bytes and UTF8 filenames remain intact")
    func binaryArchive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("原始日志.bin")
        let bytes = Data((0...255).map(UInt8.init))
        try bytes.write(to: file)
        let archive = directory.appendingPathComponent("test.zip")
        try StoredZip.write(files: [file], to: archive)
        // unzip verifies CRCs for every entry, including non-text data.
        #expect(try run("/usr/bin/unzip", ["-t", archive.path]).contains("No errors"))
    }

    @Test("Fractional timestamps preserve the exact 24 hour boundary")
    func fractionalRetention() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let firstTime = formatter.date(from: "2026-10-12T12:00:00.500Z")!
        await PersistentRuntimeLog(directory: directory, now: { firstTime }).append(source: "test", message: "precise-boundary")
        let boundaryTime = firstTime.addingTimeInterval(86400)
        let boundaryLog = PersistentRuntimeLog(directory: directory, now: { boundaryTime })
        let archive = try await boundaryLog.export()
        defer { try? FileManager.default.removeItem(atPath: archive) }
        #expect(try run("/usr/bin/unzip", ["-p", archive, "runtime.log"]).contains("precise-boundary"))
        let expiredTime = boundaryTime.addingTimeInterval(0.001)
        let expiredLog = PersistentRuntimeLog(directory: directory, now: { expiredTime })
        let expiredArchive = try await expiredLog.export()
        defer { try? FileManager.default.removeItem(atPath: expiredArchive) }
        #expect(!((try run("/usr/bin/unzip", ["-p", expiredArchive, "runtime.log"])).contains("precise-boundary")))
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self)
    }
}
