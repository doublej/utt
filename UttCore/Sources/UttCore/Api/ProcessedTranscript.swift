//
//  ProcessedTranscript.swift
//  UttCore
//
//  What every road that carries a transcript hands on: the API body, the answer to
//  an extension's clip, the panel and the history. It lived beside the pipeline that
//  builds it until that file outgrew the size rule — the tests were already here.
//

import Foundation

/// What was heard, what came out, and what happened in between.
///
/// Built once, where the pipeline runs, and threaded outward: the panel, the
/// history, an extension and an API caller all read this one object rather than
/// each reconstructing a diff of its own. Since the cleanup stage landed, the text
/// that reaches the cursor is not the text the recogniser produced, and without
/// this nothing anywhere says so.
public struct ProcessedTranscript: Equatable, Sendable {
    /// The recogniser's own output, before any stage touched it.
    public let raw: String
    /// What lands at the cursor, or goes back to the caller.
    public let text: String
    /// The stages that actually changed the words — not the ones that ran. A stage
    /// that ran and left the text alone is not worth showing anybody.
    public let stages: Set<TranscriptStage>
    /// Set when cleanup was on and did not happen. Independent of `stages`: a
    /// skipped stage changed nothing by definition.
    public let cleanupSkipped: CleanupSkipReason?
    /// How long each stretch took in milliseconds, keyed by stage name and by
    /// `decode` for the recogniser.
    ///
    /// A record parallel to `stages`, never a subset of it: a stage that ran and
    /// left the words alone took just as long, and that time is exactly what
    /// somebody chasing a slow transcription came for. Only stretches that
    /// actually ran are in it — a stage the caller skipped is absent, not zero.
    public let timings: [String: Double]
    /// Where each word of `raw` was spoken, in seconds from the start of the clip.
    ///
    /// Aligned to `raw` and never to `text`: cleanup deletes filler and the
    /// replacement rules rewrite whole phrases, so the words these numbers honestly
    /// describe are the ones the recogniser heard, not the ones that reach the
    /// cursor. Empty when the engine hands nothing back — WhisperKit does not.
    ///
    /// Deliberately absent from `CodingKeys`: the API body and the transcripts file
    /// are shapes other people already parse, and neither asked for six hundred
    /// numbers per clip. The jobs lane copies them out by hand, for an extension
    /// that declared `wantsWordTimings`.
    public let words: [SpokenWord]

    public init(
        raw: String,
        text: String,
        stages: Set<TranscriptStage> = [],
        cleanupSkipped: CleanupSkipReason? = nil,
        timings: [String: Double] = [:],
        words: [SpokenWord] = []
    ) {
        self.raw = raw
        self.text = text
        self.stages = stages
        self.cleanupSkipped = cleanupSkipped
        self.timings = timings
        self.words = words
    }

    /// True when a stage rewrote the words. Deliberately not `raw != text`: the
    /// pipeline trims, and whitespace is not something to show a person a
    /// before-and-after of.
    public var changed: Bool { !stages.isEmpty }

    /// Sorted, so the same transcript writes the same JSON twice — a `Set` would
    /// hand a watching extension a different order every time.
    public var stageNames: [String] { stages.map(\.rawValue).sorted() }

    /// The same transcript after a stage outside the settings pipeline had its
    /// turn. `raw` never moves: it is what was heard, whoever changed it since.
    ///
    /// `took` is recorded whether or not the words moved — the two are separate
    /// questions, and a filter that thought for two seconds and handed the text
    /// back unchanged spent them.
    public func applying(_ stage: TranscriptStage, text: String, took elapsed: Duration? = nil) -> Self {
        ProcessedTranscript(
            raw: raw,
            text: text,
            stages: text == self.text ? stages : stages.union([stage]),
            cleanupSkipped: cleanupSkipped,
            timings: Self.adding(elapsed, for: stage, to: timings),
            words: words
        )
    }

    /// The same transcript with one more stretch measured. Adds to what that stage
    /// already spent, so two filtering extensions are one `filter` number.
    public func timed(_ stage: TranscriptStage, _ elapsed: Duration) -> Self {
        ProcessedTranscript(
            raw: raw, text: text, stages: stages, cleanupSkipped: cleanupSkipped,
            timings: Self.adding(elapsed, for: stage, to: timings), words: words
        )
    }

    /// The same transcript with the recogniser's own word positions attached.
    ///
    /// Separate from the pipeline rather than an argument to it: `processTranscript`
    /// is given text and knows nothing about audio, and the timings arrive from the
    /// engine one level up. Nothing downstream recovers them, so this is the only
    /// place they get on board.
    public func heard(_ words: [SpokenWord]) -> Self {
        ProcessedTranscript(
            raw: raw, text: text, stages: stages, cleanupSkipped: cleanupSkipped,
            timings: timings, words: words
        )
    }

    private static func adding(
        _ elapsed: Duration?, for stage: TranscriptStage, to timings: [String: Double]
    ) -> [String: Double] {
        guard let elapsed else { return timings }
        var next = timings
        next[stage.rawValue, default: 0] += elapsed.milliseconds
        return next
    }
}

/// One word, and where it was spoken — seconds from the start of the clip it came
/// out of.
///
/// The recogniser's own unit, carried no further than the extension that asked for
/// it. Kept engine-neutral: Parakeet emits tokens and FluidAudio groups them, and a
/// second engine that learns to do this should not need a second type.
public struct SpokenWord: Codable, Equatable, Sendable {
    public var word: String
    public var start: Double
    public var end: Double

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}

/// The API's response body, and the shape every other reader was written against.
/// `text` stays exactly what it was, so a client reading only that keeps working.
extension ProcessedTranscript: Encodable {
    enum CodingKeys: String, CodingKey { case text, raw, stages, cleanupSkipped, timings }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(raw, forKey: .raw)
        try container.encode(stageNames, forKey: .stages)
        try container.encodeIfPresent(cleanupSkipped, forKey: .cleanupSkipped)
        // Absent rather than empty when nothing was measured — a transcript built
        // by hand, or by a road that does not time itself.
        if !timings.isEmpty { try container.encode(timings, forKey: .timings) }
    }
}
