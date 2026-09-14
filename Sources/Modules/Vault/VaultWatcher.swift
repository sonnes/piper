import CoreServices
import Foundation

/// Reports changes below the vault root.
///
/// The file system event stream runs on a private background queue. The handler
/// runs on the main queue. The stream groups the events of about half a second
/// into one call.
///
/// Call `start()` and `stop()` on the main thread.
public final class VaultWatcher {

    // MARK: Properties

    /// The folder that the watcher observes.
    public let root: URL

    private let handler: () -> Void
    private let latency: CFTimeInterval = 0.5
    private let queue = DispatchQueue(label: "com.piper.vault.watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var isRunning = false

    // MARK: Lifecycle

    public init(root: URL, handler: @escaping () -> Void) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.handler = handler
    }

    deinit {
        stop()
    }

    // MARK: Watching

    /// Starts the event stream. A second call does nothing.
    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            vaultWatcherCallback,
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }
        stream = created
        isRunning = true
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    /// Stops the event stream and releases it.
    public func stop() {
        isRunning = false
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func deliver() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.handler()
        }
    }
}

// MARK: - Callback

private let vaultWatcherCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue().deliver()
}
