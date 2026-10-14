import Foundation
import Synchronization

/// Ends a poll loop's wait the moment a directory it reads changes.
///
/// A kqueue watch per directory, armed by the look that first reads it, so a clip
/// renamed into a jobs directory is picked up as it lands rather than at the next
/// poll — on average 150 ms sooner. The poll stays: it is what notices a directory
/// that appeared since the last look, and anything an event missed.
///
/// A directory moved away — `ExtensionStore.remove` trashes it — leaves its watch
/// on a descriptor with no name (why `OverlayStyleStore` polls instead), so that
/// watch is dropped and the look after a reinstall arms the new one.
final class DirectoryWake: Sendable {
    private struct State {
        var sources: [String: any DispatchSourceFileSystemObject] = [:]
        var sleepers: [CheckedContinuation<Void, Never>] = []
        /// A change nobody was waiting for: the next pause returns at once, because
        /// the look before it may have missed the file that caused it.
        var pending = false
    }

    private let state = Mutex(State())

    func observe(_ directory: URL?) {
        guard let path = directory?.path else { return }
        state.withLock { state in
            guard state.sources[path] == nil else { return }
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .delete, .rename])
            source.setEventHandler { [weak self] in
                self?.changed(path, gone: !source.data.isDisjoint(with: [.delete, .rename]))
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            state.sources[path] = source
        }
    }

    /// Until `timeout`, or until a watched directory changes, whichever is first.
    func pause(for timeout: Duration) async {
        let poll = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.wake()
        }
        await withCheckedContinuation { continuation in
            let woken = state.withLock { state in
                guard !state.pending else {
                    state.pending = false
                    return true
                }
                state.sleepers.append(continuation)
                return false
            }
            if woken { continuation.resume() }
        }
        poll.cancel()
    }

    private func changed(_ path: String, gone: Bool) {
        if gone { state.withLock { $0.sources.removeValue(forKey: path) }?.cancel() }
        wake()
    }

    private func wake() {
        let sleepers = state.withLock { state in
            defer { state.sleepers = [] }
            state.pending = state.sleepers.isEmpty
            return state.sleepers
        }
        for sleeper in sleepers { sleeper.resume() }
    }
}
