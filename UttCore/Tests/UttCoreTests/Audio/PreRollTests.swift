import Testing
@testable import UttCore

private func append(_ values: [Int16], to buffer: inout PreRollBuffer) {
    values.withUnsafeBufferPointer { buffer.append($0) }
}

@Suite("PreRollBuffer")
struct PreRollBufferTests {
    @Test("an unfilled ring returns everything it has, not zero padding")
    func partialFill() {
        var buffer = PreRollBuffer(capacity: 8)
        append([1, 2, 3], to: &buffer)
        #expect(buffer.count == 3)
        #expect(buffer.tail(5) == [1, 2, 3])
    }

    @Test("the tail is the newest samples, in the order they arrived")
    func tailIsChronological() {
        var buffer = PreRollBuffer(capacity: 8)
        append([1, 2, 3, 4, 5], to: &buffer)
        #expect(buffer.tail(3) == [3, 4, 5])
    }

    @Test("writes wrap and drop the oldest samples")
    func wrapAround() {
        var buffer = PreRollBuffer(capacity: 4)
        append([1, 2, 3], to: &buffer)
        append([4, 5], to: &buffer)
        #expect(buffer.count == 4)
        #expect(buffer.tail(4) == [2, 3, 4, 5])
    }

    /// A batch longer than the ring is what a device switch produces: the tap can
    /// hand over more than a second at once, and only its tail can survive.
    @Test("a batch larger than the ring keeps only its own tail")
    func oversizedBatch() {
        var buffer = PreRollBuffer(capacity: 3)
        append([1, 2, 3, 4, 5, 6, 7], to: &buffer)
        #expect(buffer.count == 3)
        #expect(buffer.tail(3) == [5, 6, 7])
    }

    @Test("reset empties the ring rather than leaving stale audio behind")
    func resetClears() {
        var buffer = PreRollBuffer(capacity: 4)
        append([1, 2, 3, 4], to: &buffer)
        buffer.reset()
        #expect(buffer.count == 0)
        #expect(buffer.tail(4).isEmpty)
    }

    @Test("asking for nothing, or for more than exists, is not an error")
    func degenerateRequests() {
        var buffer = PreRollBuffer(capacity: 4)
        #expect(buffer.tail(2).isEmpty)
        append([9], to: &buffer)
        #expect(buffer.tail(0).isEmpty)
        #expect(buffer.tail(-1).isEmpty)
        #expect(buffer.tail(99) == [9])
    }
}

@Suite("StopGrace")
struct StopGraceTests {
    @Test("a typical 21ms block waits one block plus the margin")
    func typicalCadence() {
        #expect(StopGrace.period(tapInterval: .milliseconds(21)) == .milliseconds(29))
    }

    /// Before the first two taps land there is no cadence to measure, and the
    /// floor is what keeps that case from truncating the clip.
    @Test("an unmeasured cadence falls back to the floor")
    func zeroCadence() {
        #expect(StopGrace.period(tapInterval: .zero) == StopGrace.minimum)
    }

    @Test("a stalled tap is capped rather than making the user wait")
    func stalledCadence() {
        #expect(StopGrace.period(tapInterval: .seconds(3)) == StopGrace.maximum)
    }
}
