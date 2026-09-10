import Foundation

/// Owner-only modes for everything utt keeps on disk.
///
/// utt is not sandboxed on purpose, so its files sit in a plain directory rather
/// than a container: `settings.json` carries the API token and `history.json`
/// carries every sentence ever dictated on this Mac. Another account cannot read
/// them today only because macOS ships `~/Library/Application Support` as
/// `drwx------` — Apple's mode, not utt's, and a restore or a migration can relax
/// it without anything here noticing. So utt sets its own.
///
/// This is not a defence against the person's own processes, and nothing in the
/// interface should claim it is: with no sandbox and no TCC prompt on Application
/// Support, everything they run already reads what they can read. It closes the
/// other-account hole, and it stops a file carrying a world-readable bit with it
/// when it is copied somewhere that has no `drwx------` above it.
public enum FilePermissions {
    /// Anything holding a transcript, a credential, or audio.
    public static let file = 0o600
    /// Every directory utt creates.
    public static let directory = 0o700

    /// Passed to `createDirectory`, so a directory is never briefly wider than it
    /// should be. Computed rather than stored: `[FileAttributeKey: Any]` is not
    /// `Sendable`, and a stored static of one is a concurrency error.
    public static var directoryAttributes: [FileAttributeKey: Any] { [.posixPermissions: directory] }

    /// Narrow an item already on disk. Silent when it is not there.
    ///
    /// Best effort by design: a mode utt cannot set is not a reason to refuse to save
    /// what the person just dictated, and by the time this runs the bytes are written.
    public static func restrict(_ url: URL, to mode: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    /// Narrow everything already on disk, once, at launch.
    ///
    /// Two things need this. Files written by an earlier version are `0644`, and so is
    /// `settings.json` — `@Shared(.fileStorage)` writes it without passing through
    /// `writePrivately`. One pass fixes both and stays fixed: an atomic replace keeps
    /// the mode of the file it replaces, which is why the very first write is the only
    /// one that has to be caught.
    ///
    /// `models/` is skipped. Nothing in it is private and it holds thousands of files.
    public static func restrictExisting() {
        guard let root = try? URL.uttApplicationSupport else { return }
        restrictExisting(in: [root, try? URL.uttExtensionsDirectory, try? URL.uttRecordings].compactMap { $0 })
    }

    /// The sweep itself, over directories the caller names — the real one resolves
    /// paths a test has no business writing to.
    static func restrictExisting(in parents: [URL]) {
        for parent in parents {
            restrict(parent, to: directory)
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for item in contents where item.lastPathComponent != "models" {
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                restrict(item, to: isDirectory ? directory : file)
            }
        }
    }
}

public extension Data {
    /// Write atomically, then take the file down to owner-only.
    ///
    /// Two steps because `Data.write` takes no mode: the file is born `0644` under the
    /// usual umask and is narrowed straight after. An atomic replace keeps the mode of
    /// the file it replaces, so only the first write passes through `0644` and every
    /// rewrite after it stays `0600`.
    ///
    /// `.atomic` is write-to-temp-then-rename, which is load-bearing for its own
    /// reason: an extension polling one of these files must never read a half-written
    /// one, because its failure mode is acting on a setting nobody chose.
    func writePrivately(to url: URL) throws {
        try write(to: url, options: .atomic)
        FilePermissions.restrict(url, to: FilePermissions.file)
    }
}
