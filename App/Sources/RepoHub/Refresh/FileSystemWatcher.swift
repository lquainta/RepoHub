import CoreServices
import Foundation

/// Watches folders for changes. ``FSEventsWatcher`` is the real implementation;
/// tests inject fakes.
@MainActor
protocol FileWatching: AnyObject {
    /// Starts watching `folders`, replacing any previous set. `onChange` gets
    /// batches of changed paths on the main actor.
    func watch(_ folders: [String], onChange: @escaping @MainActor ([String]) -> Void)
    /// Stops watching.
    func stop()
}

/// Watches folders recursively with FSEvents.
///
/// FSEvents coalesces events for `latency` seconds, so a burst of writes (a
/// checkout, a build) arrives as one batch.
@MainActor
final class FSEventsWatcher: FileWatching {
    private var stream: FSEventStreamRef?
    private var handler: Handler?
    private let latency: CFTimeInterval
    private let queue = DispatchQueue(label: "com.lquainta.RepoHub.fsevents")

    /// Receives callbacks from FSEvents and forwards them to the main actor.
    fileprivate final class Handler: Sendable {
        let onChange: @MainActor @Sendable ([String]) -> Void

        init(onChange: @escaping @MainActor @Sendable ([String]) -> Void) {
            self.onChange = onChange
        }
    }

    init(latency: CFTimeInterval = 0.3) {
        self.latency = latency
    }

    isolated deinit {
        stop()
    }

    func watch(_ folders: [String], onChange: @escaping @MainActor ([String]) -> Void) {
        stop()
        guard !folders.isEmpty else {
            return
        }
        let callback = onChange
        let handler = Handler { paths in callback(paths) }
        self.handler = handler

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let stream = FSEventStreamCreate(
                nil,
                fsEventsCallback,
                &context,
                folders as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            )
        else {
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        handler = nil
    }
}

// The parameter list is fixed by FSEventStreamCallback.
// swiftlint:disable function_parameter_count

/// The FSEvents C callback. It runs on the watcher's dispatch queue, so it must
/// be a nonisolated function: a closure written inside the `@MainActor` class
/// would inherit main-actor isolation, and Swift's runtime check would trap
/// when FSEvents calls it from another queue.
private func fsEventsCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else {
        return
    }
    let handler = Unmanaged<FSEventsWatcher.Handler>.fromOpaque(info).takeUnretainedValue()
    let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
    Task { @MainActor in handler.onChange(paths) }
}

// swiftlint:enable function_parameter_count
