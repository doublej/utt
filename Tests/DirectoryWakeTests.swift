import Foundation
import Testing
@testable import utt

/// The jobs lane's wake-up: a clip landing in a watched directory ends the wait long
/// before the poll would have, and one landing while nobody waits is not lost.
@Suite("Directory wake")
struct DirectoryWakeTests {
    @Test("a clip renamed into a watched directory ends the pause")
    func renameWakes() async throws {
        let directory = try Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wake = DirectoryWake()
        wake.observe(directory)
        let staged = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        try Data().write(to: staged)
        let start = ContinuousClock.now
        async let paused: Void = wake.pause(for: .seconds(10))
        try await Task.sleep(for: .milliseconds(50))
        try FileManager.default.moveItem(at: staged, to: directory.appending(path: "clip.wav"))
        await paused
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test("a change nobody was waiting for makes the next pause return at once")
    func pendingChange() async throws {
        let directory = try Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wake = DirectoryWake()
        wake.observe(directory)
        try Data().write(to: directory.appending(path: "clip.wav"))
        try await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        await wake.pause(for: .seconds(10))
        #expect(start.duration(to: .now) < .seconds(2))
    }

    private static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "wake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
