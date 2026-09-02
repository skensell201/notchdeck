import Testing
@testable import NotchCore

@Suite("Scroll accumulator")
struct ScrollAccumulatorTests {
    private func makeAccumulator() -> ScrollAccumulator {
        ScrollAccumulator(thresholds: .init(vertical: 30, horizontal: 45))
    }

    @Test("deltas below the threshold produce no gesture")
    func belowThresholdIsSilent() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: 0, deltaY: 10, phase: .began) == nil)
        #expect(accumulator.consume(deltaX: 0, deltaY: 10, phase: .changed) == nil)
    }

    @Test("accumulated downward deltas open the notch")
    func downwardOpens() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 12, phase: .began)
        _ = accumulator.consume(deltaX: 0, deltaY: 12, phase: .changed)

        #expect(accumulator.consume(deltaX: 0, deltaY: 12, phase: .changed) == .open)
    }

    @Test("accumulated upward deltas close the notch")
    func upwardCloses() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: -20, phase: .began)

        #expect(accumulator.consume(deltaX: 0, deltaY: -20, phase: .changed) == .close)
    }

    @Test("a swipe fires only once until the gesture ends")
    func gestureLocksAfterFiring() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 40, phase: .began)

        #expect(accumulator.consume(deltaX: 0, deltaY: 40, phase: .changed) == nil)
    }

    @Test("ending the gesture rearms the accumulator")
    func endRearms() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 40, phase: .began)
        _ = accumulator.consume(deltaX: 0, deltaY: 0, phase: .ended)

        #expect(accumulator.consume(deltaX: 0, deltaY: 40, phase: .began) == .open)
    }

    @Test("a rightward swipe asks for the previous track")
    func rightwardIsPrevious() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: 50, deltaY: 2, phase: .began) == .previousTrack)
    }

    @Test("a leftward swipe asks for the next track")
    func leftwardIsNext() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: -50, deltaY: 2, phase: .began) == .nextTrack)
    }

    @Test("the dominant axis wins when both cross their thresholds")
    func dominantAxisWins() {
        var accumulator = makeAccumulator()

        #expect(accumulator.consume(deltaX: 46, deltaY: 90, phase: .began) == .open)
    }

    @Test("starting a new gesture discards leftovers from the previous one")
    func beganResetsAccumulation() {
        var accumulator = makeAccumulator()
        _ = accumulator.consume(deltaX: 0, deltaY: 25, phase: .began)

        #expect(accumulator.consume(deltaX: 0, deltaY: 25, phase: .began) == nil)
    }
}
