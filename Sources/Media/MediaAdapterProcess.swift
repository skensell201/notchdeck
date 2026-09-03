import Foundation
import Support

/// Absolute paths to the vendored adapter inside the app bundle. The perl script
/// derives the dylib name from the framework directory's basename, so neither can
/// be renamed independently, and both paths must be absolute — a relative one
/// passes the existence check and then fails at load.
public struct AdapterPaths: Sendable {
    public let script: URL
    public let framework: URL

    public init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
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
        return AdapterPaths(script: script, framework: framework)
    }

    func arguments(_ command: [String]) -> [String] {
        [script.path(percentEncoded: false), framework.path(percentEncoded: false)] + command
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
/// object. `--micros` gives integer epoch microseconds instead of an ISO date, and
/// `--debounce` coalesces the two-line bursts a single state change produces.
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
                guard !chunk.isEmpty else { return }
                for text in buffer.consuming(chunk) {
                    continuation.yield(text)
                }
            }

            process.terminationHandler = { [weak self] finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.logger.notice("adapter stream exited with status \(finished.terminationStatus, privacy: .public)")
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }

            do {
                try process.run()
                lock.withLock { self.process = process }
            } catch {
                logger.error("could not start the adapter: \(error.localizedDescription, privacy: .public)")
                continuation.finish()
            }
        }
    }

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
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/perl")
            process.arguments = paths.arguments(arguments)
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

    /// Runs the adapter's `test` command, which exits 0 when MediaRemote access
    /// genuinely works. Used once at launch to decide whether to degrade.
    public func probe() async -> Bool {
        await run(arguments: ["test"])
    }
}
