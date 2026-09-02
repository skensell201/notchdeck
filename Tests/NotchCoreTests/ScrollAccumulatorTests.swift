import Testing
@testable import NotchCore

@Suite("Scroll accumulator")
struct ScrollAccumulatorTests {
    private func makeAccumulator() -> ScrollAccumulator {
        ScrollAccumulator(configuration: .init(vertical: 30, horizontal: 45, idleInterval: 0.15))
    }

    @Test("deltas below the threshold produce no gesture")
    func belowThresholdIsSilent() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: 0, deltaY: 10, phase: .began, timestamp: 0) == nil)
        #expect(accumulator.consume(deltaX: 0, deltaY: 10, phase: .changed, timestamp: 0.02) == nil)
    }

    @Test("accumulated downward deltas open the notch")
    func downwardOpens() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 12, phase: .began, timestamp: 0)
        _ = accumulator.consume(deltaX: 0, deltaY: 12, phase: .changed, timestamp: 0.02)

        #expect(accumulator.consume(deltaX: 0, deltaY: 12, phase: .changed, timestamp: 0.04) == .down)
    }

    @Test("accumulated upward deltas close the notch")
    func upwardCloses() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: -20, phase: .began, timestamp: 0)

        #expect(accumulator.consume(deltaX: 0, deltaY: -20, phase: .changed, timestamp: 0.02) == .up)
    }

    @Test("a swipe fires only once until the gesture ends")
    func gestureLocksAfterFiring() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 40, phase: .began, timestamp: 0)

        #expect(accumulator.consume(deltaX: 0, deltaY: 40, phase: .changed, timestamp: 0.02) == nil)
    }

    @Test("ending the gesture rearms the accumulator")
    func endRearms() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 40, phase: .began, timestamp: 0)
        _ = accumulator.consume(deltaX: 0, deltaY: 0, phase: .ended, timestamp: 0.02)

        #expect(accumulator.consume(deltaX: 0, deltaY: 40, phase: .began, timestamp: 0.04) == .down)
    }

    @Test("a rightward swipe scrolls right")
    func rightwardIsRight() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: 50, deltaY: 2, phase: .began, timestamp: 0) == .right)
    }

    @Test("a leftward swipe scrolls left")
    func leftwardIsLeft() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: -50, deltaY: 2, phase: .began, timestamp: 0) == .left)
    }

    @Test("the dominant axis wins when both cross their thresholds")
    func dominantAxisWins() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: 46, deltaY: 90, phase: .began, timestamp: 0) == .down)
    }

    @Test("starting a new gesture discards leftovers from the previous one")
    func beganResetsAccumulation() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 25, phase: .began, timestamp: 0)

        #expect(accumulator.consume(deltaX: 0, deltaY: 25, phase: .began, timestamp: 0.02) == nil)
    }

    @Test("the momentum tail of a flick cannot fire a second gesture")
    func momentumIsIgnored() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 20, phase: .began, timestamp: 0)
        #expect(accumulator.consume(deltaX: 0, deltaY: 20, phase: .changed, timestamp: 0.02) == .down)
        _ = accumulator.consume(deltaX: 0, deltaY: 0, phase: .ended, timestamp: 0.04)

        #expect(accumulator.consume(deltaX: 0, deltaY: 25, phase: .momentum, timestamp: 0.06) == nil)
        #expect(accumulator.consume(deltaX: 0, deltaY: 25, phase: .momentum, timestamp: 0.08) == nil)
    }

    @Test("a wheel that never sends a phase fires again after an idle gap")
    func discreteRearmsAfterIdleGap() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: 0, deltaY: 40, phase: .discrete, timestamp: 0) == .down)
        #expect(accumulator.consume(deltaX: 0, deltaY: 40, phase: .discrete, timestamp: 0.05) == nil)
        #expect(accumulator.consume(deltaX: 0, deltaY: 40, phase: .discrete, timestamp: 1) == .down)
    }

    @Test("discrete deltas inside the idle interval accumulate into one gesture")
    func discreteDeltasAccumulate() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: 0, deltaY: 12, phase: .discrete, timestamp: 0) == nil)
        #expect(accumulator.consume(deltaX: 0, deltaY: 12, phase: .discrete, timestamp: 0.05) == nil)
        #expect(accumulator.consume(deltaX: 0, deltaY: 12, phase: .discrete, timestamp: 0.1) == .down)
    }

    @Test("an almost vertical swipe never reports a horizontal direction")
    func horizontalNeedsDominance() {
        var accumulator = ScrollAccumulator(
            configuration: .init(vertical: 100, horizontal: 10, idleInterval: 0.15)
        )

        #expect(accumulator.consume(deltaX: 11, deltaY: 90, phase: .began, timestamp: 0) == nil)
        #expect(accumulator.consume(deltaX: 0, deltaY: 20, phase: .changed, timestamp: 0.02) == .down)
    }
}
