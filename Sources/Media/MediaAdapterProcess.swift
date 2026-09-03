import Foundation
import Support

/// Absolute paths to the vendored adapter inside the app bundle. The perl script
/// derives the dylib name from the framework directory's basename, so neither can
/// be renamed independently, and both paths must be absolute — a relative one
/// passes the existence check and then fails at load.
public struct AdapterPaths: Sendable {
    public let script: URL
    public let framework: URL
    /// Absolute path to the bundled `MediaRemoteAdapterTestClient`, when present.
    /// Only the `test` probe uses it — see `arguments(_:includeTestClient:)`.
    public let testClient: URL?

    public init(script: URL, framework: URL, testClient: URL? = nil) {
        self.script = script
        self.framework = framework
        self.testClient = testClient
    }

    public static func inMainBundle(_ bundle: Bundle = .main) -> AdapterPaths? {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = bundle.privateFrameworksURL else {
            return nil
        }
        let framework = frameworks.appending(path: "MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path(percentEncoded: false)) else {
            return nil
        }
        let testClientCandidate = bundle.bundleURL.appending(path: "Contents/MacOS/MediaRemoteAdapterTestClient")
        let testClient = FileManager.default.fileExists(atPath: testClientCandidate.path(percentEncoded: false))
            ? testClientCandidate
            : nil
        return AdapterPaths(script: script, framework: framework, testClient: testClient)
    }

    /// Builds the perl invocation's arguments. The vendored script's usage is
    /// `FRAMEWORK_PATH [TEST_CLIENT_PATH] FUNCTION [PARAMS|OPTIONS...]` — the test
    /// client path is recognised only because it contains a "/", so it must sit
    /// between the framework path and the command, never among the command's own
    /// arguments. Only `probe()` passes `includeTestClient: true`: without the
    /// client, `test` silently degrades to a plain `get` and proves nothing.
    func arguments(_ command: [String], includeTestClient: Bool = false) -> [String] {
        var arguments = [script.path(percentEncoded: false), framework.path(percentEncoded: false)]
        if includeTestClient, let testClient {
            arguments.append(testClient.path(percentEncoded: false))
        }
        arguments += command
        return arguments
    }
}

public enum AdapterBackoff {
    public static let maximumDelay: Duration = .seconds(30)

    /// The first restart is immediate, so a single crash is invisible to the user;
    /// after that the delay doubles up to the cap.
    public static func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 0 else { return .zero }
        let seconds = min(pow(2.0, Double(attempt - 1)), 30)
        return min(.seconds(seconds), maximumDelay)
    }
}

/// A source of NDJSON lines from the adapter's `stream` command.
public protocol AdapterStreamSource: Sendable {
    /// Lines until the underlying process exits. Long silences are normal.
    func lines() -> AsyncStream<String>
    func stop()
}

/// Accumulates raw bytes from the adapter's stdout pipe and splits them into
/// lines. Strict concurrency rejects a plain `var` captured by the pipe's
/// `readabilityHandler` closure (it runs on a dispatch queue, not in-line), so the
/// buffer is boxed here and guarded by the same lock `PerlAdapterStream` already
/// uses for `process`, rather than weakening the stream's Sendable conformance.
private final class LineBuffer: @unchecked Sendable {
    private let lock: NSLock
    private var data = Data()

    init(lock: NSLock) {
        self.lock = lock
    }

    /// Appends a chunk and returns the complete lines it produced, if any.
    func consuming(_ chunk: Data) -> [String] {
        lock.withLock {
            data.append(chunk)
            var lines: [String] = []
            while let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                let line = data[data.startIndex..<newline]
                data.removeSubrange(data.startIndex...newline)
                if let text = String(data: line, encoding: .utf8) {
                    lines.append(text)
                }
            }
            return lines
        }
    }
}

/// Spawns `/usr/bin/perl` on the vendored adapter and yields one line per JSON
/// object. `--micros` gives integer epoch microseconds instead of an ISO date.
/// `--debounce` does *not* coalesce the two-line bursts a single state change
/// produces: in the adapter's `stream.m`, only the `NowPlayingInfoDidChange`
/// observer is debounced — `IsPlayingDidChange` still dispatches immediately — so
/// the flag stretches such a burst to at least the debounce delay rather than
/// merging it into one line. Coalescing the burst, if it is ever needed, is this
/// stream's consumer's job.
public final class PerlAdapterStream: AdapterStreamSource, @unchecked Sendable {
    private let paths: AdapterPaths
    private let logger = Log.make("media.adapter")
    private let lock = NSLock()
    private var process: Process?

    public init(paths: AdapterPaths) {
        self.paths = paths
    }

    public func lines() -> AsyncStream<String> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/perl")
            process.arguments = paths.arguments(["stream", "--micros", "--debounce=50"])

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            let buffer = LineBuffer(lock: lock)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    // An empty chunk at this handler means EOF on the read end. If
                    // the handler is left in place, a persistent EOF (e.g. an
                    // unlaunched process whose Pipe gets released) fires it
                    // continuously — measured at over 500,000 calls/s, pinning a
                    // core. Clear it so EOF is handled once, not spun on.
                    handle.readabilityHandler = nil
                    return
                }
                for text in buffer.consuming(chunk) {
                    continuation.yield(text)
                }
            }

            process.terminationHandler = { [weak self] finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.logger.notice("adapter stream exited with status \(finished.terminationStatus, privacy: .public)")
                continuation.finish()
            }

            do {
                try process.run()
                lock.withLock { self.process = process }
                // Capture `process` directly rather than going through `self`: if
                // this `PerlAdapterStream` is released while its AsyncStream is
                // still being consumed, cancellation must still reach the specific
                // subprocess this call started, not whatever `self.process`
                // happens to hold by then (a later `lines()` call would have
                // overwritten it). `terminate()` on a process that has already
                // exited — e.g. via `terminationHandler` above — is a no-op;
                // verified this doesn't throw. It does throw, however, on a
                // process that was never launched, which is why this is set only
                // after `process.run()` succeeds.
                continuation.onTermination = { _ in
                    process.terminate()
                }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                logger.error("could not start the adapter: \(error.localizedDescription, privacy: .public)")
                continuation.finish()
            }
        }
    }

    /// Terminates the most recently started process, if any. `lines()`'s own
    /// `continuation.onTermination` is the reliable teardown path for a given
    /// stream — this is a convenience for callers holding onto the stream object.
    public func stop() {
        let running = lock.withLock { () -> Process? in
            defer { process = nil }
            return process
        }
        running?.terminate()
    }
}

/// Runs one-shot adapter commands.
public struct PerlAdapterCommandRunner: AdapterCommandRunner {
    private let paths: AdapterPaths

    public init(paths: AdapterPaths) {
        self.paths = paths
    }

    public func run(arguments: [String]) async -> Bool {
        await run(arguments: arguments, includeTestClient: false)
    }

    /// Runs the adapter's `test` command, which exits 0 when MediaRemote access
    /// genuinely works. Used once at launch to decide whether to degrade. Passes
    /// the bundled test client — without it, `test` degrades to a plain `get` and
    /// proves nothing.
    public func probe() async -> Bool {
        await run(arguments: ["test"], includeTestClient: true)
    }

    private func run(arguments: [String], includeTestClient: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/perl")
            process.arguments = paths.arguments(arguments, includeTestClient: includeTestClient)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
