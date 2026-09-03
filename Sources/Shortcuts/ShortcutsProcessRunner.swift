import Foundation
import Support

/// Accumulates a subprocess's stdout as it arrives. Reading only after the
/// process exits (`readDataToEndOfFile` in a termination handler) risks a
/// classic `Process` deadlock: the pipe has a fixed kernel buffer, and a child
/// that fills it while nobody is draining blocks forever writing, which means
/// it never exits, which means the parent never gets to read. Draining via
/// `readabilityHandler` as data arrives — the same shape `PerlAdapterStream`
/// uses for its line buffer — avoids that regardless of how much `shortcuts
/// list` ever prints. Guarded by a lock because the handler runs on a
/// dispatch queue, not in-line, and the termination handler can race it.
private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk) }
    }

    var text: String {
        lock.withLock { String(data: data, encoding: .utf8) ?? "" }
    }
}

/// Shells out to `/usr/bin/shortcuts`. The only implementation of
/// `ShortcutsRunning` that knows `Process` exists.
public struct ShortcutsProcessRunner: ShortcutsRunning {
    private static let executableURL = URL(filePath: "/usr/bin/shortcuts")

    public init() {}

    public func list() async throws -> [String] {
        let result = await execute(["list"])
        guard let result else { throw ShortcutsProcessError.launchFailed }
        guard result.exitCode == 0 else { throw ShortcutsProcessError.nonZeroExit(result.exitCode) }
        return ShortcutsListParser.parse(result.standardOutput)
    }

    public func run(name: String) async -> Bool {
        await execute(["run", name])?.exitCode == 0
    }

    private func execute(_ arguments: [String]) async -> (exitCode: Int32, standardOutput: String)? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = Self.executableURL
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            let buffer = ProcessOutputBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    // Empty data at this handler means EOF; clearing it stops the
                    // handler from being re-invoked continuously once the read
                    // end is closed. See `PerlAdapterStream` for the same fix.
                    handle.readabilityHandler = nil
                    return
                }
                buffer.append(chunk)
            }

            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                // Whatever arrived between the last readability callback and
                // termination is still sitting in the pipe; drain it once more.
                buffer.append(pipe.fileHandleForReading.availableData)
                continuation.resume(returning: (finished.terminationStatus, buffer.text))
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
