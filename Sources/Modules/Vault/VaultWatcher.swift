import CoreServices
import Foundation

/// Reports changes below the root of a vault.
///
/// The file system event stream runs on a private background queue. The handler
/// runs on the main queue. The stream groups the events of about half a second
/// into one call. A watcher with a `part` reports only the changes to a path
/// that contains that part.
///
/// Call `start()` and `stop()` on the main thread.
public final class VaultWatcher {

    // MARK: Properties

    public let vault: Vault

    private let part: String?
    private let handler: () -> Void
    private let latency: CFTimeInterval = 0.5
    private let queue = DispatchQueue(label: "com.piper.vault.watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var relay: Relay?
    private var isRunning = false

    // MARK: Lifecycle

    /// - Parameter part: A part of a path, such as `/.claude`. Nil reports every change.
    public init(vault: Vault, part: String? = nil, handler: @escaping () -> Void) {
        self.vault = vault
        self.part = part
        self.handler = handler
    }

    deinit {
        stop()
    }

    // MARK: Watching

    /// Starts the event stream. A second call does nothing.
    public func start() {
        guard stream == nil else { return }
        let relay = Relay(watcher: self, part: part)
        self.relay = relay
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(relay).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            vaultWatcherCallback,
            &context,
            [vault.root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }
        stream = created
        isRunning = true
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    public func stop() {
        isRunning = false
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        queue.sync {}
        FSEventStreamRelease(stream)
        self.stream = nil
        relay = nil
    }

    fileprivate func fire() {
        guard isRunning else { return }
        handler()
    }
}

// MARK: - Callback

/// What the stream calls. The callback runs on the queue of the stream, so it
/// never holds the watcher: the last release of a watcher must happen on the main thread.
private final class Relay {
    weak var watcher: VaultWatcher?
    let part: String?

    init(watcher: VaultWatcher, part: String?) {
        self.watcher = watcher
        self.part = part
    }

    func deliver(_ paths: [String]) {
        if let part, !paths.contains(where: { $0.contains(part) }) { return }
        DispatchQueue.main.async { [self] in watcher?.fire() }
    }
}

private let vaultWatcherCallback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
    guard let info else { return }
    let list = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    let paths = (0..<count).map { String(cString: list[$0]) }
    Unmanaged<Relay>.fromOpaque(info).takeUnretainedValue().deliver(paths)
}
