import Foundation
import Testing
@testable import SystemHUD

final class FakeAgentControl: OSDAgentControlling, @unchecked Sendable {
    var runningPIDs: [Int32] = []
    var suspended: [Int32] = []
    var resumed: [Int32] = []

    func runningAgentPIDs() -> [Int32] { runningPIDs }
    func suspend(_ pid: Int32) { suspended.append(pid) }
    func resume(_ pid: Int32) { resumed.append(pid) }
}

@Suite("OSD suppression")
struct OSDSuppressionTests {
    @Test("suppressing a running agent suspends it")
    func suspendsRunningAgent() {
        let control = FakeAgentControl()
        control.runningPIDs = [4242]
        let suppressor = OSDSuppressor(control: control)

        suppressor.enforce()

        #expect(control.suspended == [4242])
    }

    @Test("an agent that respawns under a new pid is suspended again")
    func respawnIsCaughtOnTheNextPass() {
        let control = FakeAgentControl()
        control.runningPIDs = [1]
        let suppressor = OSDSuppressor(control: control)
        suppressor.enforce()

        control.runningPIDs = [2]
        suppressor.enforce()

        #expect(control.suspended == [1, 2])
    }

    @Test("an already-suspended agent is not suspended twice")
    func idempotentWithinOnePid() {
        let control = FakeAgentControl()
        control.runningPIDs = [7]
        let suppressor = OSDSuppressor(control: control)

        suppressor.enforce()
        suppressor.enforce()
        suppressor.enforce()

        #expect(control.suspended == [7])
    }

    @Test("nothing is suspended when the agent is not running")
    func noAgentIsANoOp() {
        let control = FakeAgentControl()
        let suppressor = OSDSuppressor(control: control)

        suppressor.enforce()

        #expect(control.suspended.isEmpty)
    }

    @Test("restoring resumes every agent it suspended")
    func restoreResumesAll() {
        let control = FakeAgentControl()
        control.runningPIDs = [1]
        let suppressor = OSDSuppressor(control: control)
        suppressor.enforce()
        control.runningPIDs = [2]
        suppressor.enforce()

        suppressor.restore()

        #expect(control.resumed == [1, 2])
    }

    @Test("restoring twice does not resume anything twice")
    func restoreIsIdempotent() {
        let control = FakeAgentControl()
        control.runningPIDs = [9]
        let suppressor = OSDSuppressor(control: control)
        suppressor.enforce()

        suppressor.restore()
        suppressor.restore()

        #expect(control.resumed == [9])
    }

    @Test("enforcing again after a restore starts from a clean slate")
    func enforceAfterRestoreWorks() {
        let control = FakeAgentControl()
        control.runningPIDs = [5]
        let suppressor = OSDSuppressor(control: control)
        suppressor.enforce()
        suppressor.restore()

        suppressor.enforce()

        #expect(control.suspended == [5, 5])
    }
}
