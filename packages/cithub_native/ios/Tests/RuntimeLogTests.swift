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
