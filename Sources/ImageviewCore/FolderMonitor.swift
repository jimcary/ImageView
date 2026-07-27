import Darwin
import Foundation

public final class FolderMonitor: @unchecked Sendable {
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.local.Imageview.folder-monitor")
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var pendingWorkItem: DispatchWorkItem?

    public init(debounceInterval: TimeInterval = 0.2) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stop()
    }

    public func start(
        url: URL,
        onChange: @escaping @Sendable () -> Void
    ) throws {
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: url.path]
            )
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
            queue: queue
        )
        newSource.setEventHandler { [weak self] in
            self?.schedule(onChange)
        }
        newSource.setCancelHandler {
            close(descriptor)
        }

        lock.lock()
        source = newSource
        lock.unlock()
        newSource.resume()
    }

    public func stop() {
        lock.lock()
        let oldSource = source
        source = nil
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        lock.unlock()
        oldSource?.cancel()
    }

    private func schedule(_ onChange: @escaping @Sendable () -> Void) {
        let workItem = DispatchWorkItem(block: onChange)
        lock.lock()
        pendingWorkItem?.cancel()
        pendingWorkItem = workItem
        lock.unlock()
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
