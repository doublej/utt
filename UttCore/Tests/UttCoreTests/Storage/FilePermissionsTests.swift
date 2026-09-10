import Foundation
import Testing
@testable import UttCore

@Suite("File permissions")
struct FilePermissionsTests {
    /// A scratch directory of its own, so a failing test cannot widen anything real.
    private func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(component: "utt-permissions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    /// The whole fix. `Data.write` has no mode parameter, so a plain write lands at
    /// `0644` under the usual umask — world-readable, for a file that holds the API
    /// token or a transcript.
    @Test
    func aPrivateWriteIsOwnerOnly() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(component: "values.json")

        try Data(#"{"token":"secret"}"#.utf8).writePrivately(to: url)

        #expect(try mode(of: url) == 0o600)
    }

    /// Every write after the first is an atomic replace, which keeps the mode of the
    /// file it replaces. If that ever stopped being true, one rewrite would silently
    /// widen the file back and nothing else here would catch it.
    @Test
    func rewritingKeepsItOwnerOnly() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(component: "values.json")

        try Data("{}".utf8).writePrivately(to: url)
        try Data(#"{"revision":2}"#.utf8).write(to: url, options: .atomic)

        #expect(try mode(of: url) == 0o600)
    }

    /// Files an earlier version wrote are `0644`, and so is `settings.json`, which
    /// `@Shared(.fileStorage)` writes without passing through `writePrivately`. The
    /// launch sweep is the only thing that reaches those.
    @Test
    func restrictNarrowsAFileThatIsAlreadyWide() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(component: "settings.json")
        try Data("{}".utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        FilePermissions.restrict(url, to: FilePermissions.file)

        #expect(try mode(of: url) == 0o600)
    }

    /// Best effort by design: a mode utt cannot set is not a reason to trap. The
    /// callers run right after writing something the person dictated.
    @Test
    func restrictIsSilentAboutAFileThatIsNotThere() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        FilePermissions.restrict(directory.appending(component: "gone.json"), to: FilePermissions.file)
    }

    /// What the launch sweep is for: a tree left behind by an earlier version, where
    /// the token, the transcripts and the directory holding them are all world-readable.
    /// `models/` is the one thing it must leave alone — nothing in it is private and it
    /// holds thousands of files.
    @Test
    func theSweepNarrowsAnExistingTreeButSkipsModels() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let extensions = root.appending(component: "extensions")
        let models = root.appending(component: "models")
        for directory in [extensions, models] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        }
        let wide = [
            root.appending(component: "settings.json"),
            root.appending(component: "history.json"),
            extensions.appending(component: "deckhand.values.json")
        ]
        for url in wide {
            try Data("{}".utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }

        FilePermissions.restrictExisting(in: [root, extensions])

        for url in wide { #expect(try mode(of: url) == 0o600) }
        #expect(try mode(of: root) == 0o700)
        #expect(try mode(of: extensions) == 0o700)
        #expect(try mode(of: models) == 0o755)
    }

    /// The directory mode is the part that actually gates another account, so it has
    /// to be set at creation rather than after — a directory that is briefly `0755`
    /// is a directory something could have walked into.
    @Test
    func aCreatedDirectoryIsOwnerOnly() throws {
        let parent = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let url = parent.appending(component: "extensions")

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: FilePermissions.directoryAttributes
        )

        #expect(try mode(of: url) == 0o700)
    }
}
