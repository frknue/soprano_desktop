import Darwin
import Foundation

/// An exclusive `flock` on `state.lock` next to state.json, held for a whole sync, apply or
/// restore, so the CLI and the running app never interleave their reads and writes of
/// state.json (or of the settings they record). The kernel drops the lock when the process
/// exits, so a crash never leaves it held.
final class StateLock {
    private let url: URL
    private var descriptor: Int32 = -1

    init(url: URL) {
        self.url = url
    }

    deinit {
        unlock()
    }

    /// `wait`: block until the other process is done (the CLI); else return false at once
    /// when it is held (the app, which retries later).
    func lock(wait: Bool) -> Bool {
        guard descriptor < 0 else { return true }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | (wait ? 0 : LOCK_NB)) != 0 {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }

    func unlock() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
