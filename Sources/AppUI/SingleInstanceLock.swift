import Darwin
import Foundation

final class SingleInstanceLock {
    private let lockFileURL: URL
    private var fileDescriptor: CInt = -1

    init(lockFileURL: URL = SingleInstanceLock.defaultLockFileURL()) throws {
        self.lockFileURL = lockFileURL
        try FileManager.default.createDirectory(
            at: lockFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        fileDescriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func tryAcquire() throws -> Bool {
        guard fileDescriptor >= 0 else {
            throw POSIXError(.EBADF)
        }

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            return true
        }

        if errno == EWOULDBLOCK {
            return false
        }

        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    func release() {
        guard fileDescriptor >= 0 else {
            return
        }
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    deinit {
        release()
    }

    private static func defaultLockFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Scrawl", isDirectory: true)
            .appendingPathComponent("Scrawl.lock")
    }
}
