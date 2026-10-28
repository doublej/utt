import Testing
@testable import UttCore

@Suite("Writing split")
struct WritingSplitTests {
    @Test
    func theFirstWordsAreAllNew() {
        #expect(WritingSplit.settled(previous: "", current: "hello") == "")
    }

    @Test
    func appendedWordsLeaveTheShownOnesAlone() {
        #expect(WritingSplit.settled(previous: "hello", current: "hello world") == "hello")
    }

    /// A word still being heard keeps growing from where it was.
    @Test
    func growthMidWordKeepsTheLettersShown() {
        #expect(WritingSplit.settled(previous: "the wor", current: "the world") == "the wor")
    }

    @Test
    func aRevisedWordIsWrittenAgainWhole() {
        #expect(WritingSplit.settled(previous: "the cat sat", current: "the car sat") == "the ")
    }

    @Test
    func aRevisedFirstWordRewritesFromTheStart() {
        #expect(WritingSplit.settled(previous: "cat", current: "car") == "")
    }

    @Test
    func shrinkingWritesNothingNew() {
        #expect(WritingSplit.settled(previous: "hello world", current: "hello") == "hello")
    }
}
