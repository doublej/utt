/// A fixed-size ring of 16 kHz mono samples holding the most recent second of
/// audio, so a recording can begin slightly *before* the keypress that started it.
///
/// People start speaking as they reach for the hotkey, not after it — without this,
/// the first syllable is already gone by the time the engine opens.
///
/// Deliberately over-sized relative to the pre-roll actually used: a full second is
/// 32 KB, and the headroom means a tap that arrives late still finds a complete
/// window rather than a partial one.
public struct PreRollBuffer: Sendable {
    private var samples: [Int16]
    private var writeIndex = 0
    private var filled = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "a ring with no room is not a ring")
        samples = Array(repeating: 0, count: capacity)
    }

    public var capacity: Int { samples.count }
    public var count: Int { filled }

    /// Takes an `UnsafeBufferPointer` rather than an `Array` because the only caller
    /// is a real-time audio tap: building an array per tap would allocate on the
    /// audio thread, which is the one place allocation is not free.
    public mutating func append(_ incoming: UnsafeBufferPointer<Int16>) {
        // Anything beyond the last `capacity` samples of this batch is about to be
        // overwritten by the rest of the same batch, so never copy it at all.
        let start = max(0, incoming.count - samples.count)
        for index in start..<incoming.count {
            samples[writeIndex] = incoming[index]
            writeIndex = (writeIndex + 1) % samples.count
        }
        filled = min(filled + (incoming.count - start), samples.count)
    }

    /// The most recent `wanted` samples in chronological order, or everything held
    /// so far if the ring has not filled up yet.
    public func tail(_ wanted: Int) -> [Int16] {
        let take = min(max(wanted, 0), filled)
        guard take > 0 else { return [] }
        var output = [Int16](repeating: 0, count: take)
        var index = (writeIndex - take + samples.count) % samples.count
        for position in 0..<take {
            output[position] = samples[index]
            index = (index + 1) % samples.count
        }
        return output
    }

    /// Called when a recording ends: what is left in the ring is audio the user has
    /// already had transcribed, and replaying it into the next clip would duplicate
    /// their last half-second of speech.
    public mutating func reset() {
        writeIndex = 0
        filled = 0
    }
}
