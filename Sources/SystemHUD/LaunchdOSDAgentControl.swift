import Foundation
import Support

/// Finds and signals `OSDUIHelper`, the undocumented agent that draws the system
/// volume overlay.
///
/// `SIGSTOP` rather than `SIGKILL`: killing it makes launchd respawn it at once,
/// while stopping it leaves a process we can resume exactly as we found it.
public struct LaunchdOSDAgentControl: OSDAgentControlling {
    private static let agentName = "OSDUIHelper"
    private let logger = Log.make("system-hud")

    public init() {}

    public func runningAgentPIDs() -> [Int32] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        process.arguments = ["-x", Self.agentName]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("could not look for \(Self.agentName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    public func suspend(_ pid: Int32) {
        if kill(pid, SIGSTOP) != 0 {
            logger.notice("could not suspend \(Self.agentName, privacy: .public) \(pid, privacy: .public)")
        }
    }

    public func resume(_ pid: Int32) {
        // A pid that has already gone is not an error worth reporting: the agent
        // exiting is exactly what we wanted to be able to survive.
        _ = kill(pid, SIGCONT)
    }
}
