//
//  ScenarioRunner.swift
//  UttCoreTests
//
//  Table-driven driver for HotKeyProcessor. Each step names an absolute time on a
//  scrubbed clock, so the suite never sleeps and never reads the wall clock.
//

import Dependencies
import Foundation
import Testing
@testable import UttCore

/// A single keyboard chord delivered to the processor at a fixed point in time.
struct ScenarioStep {
    /// The time offset (in seconds) relative to the scenario start.
    let time: TimeInterval

    /// Which key (if any) is pressed in this chord.
    let key: Key?

    /// Which modifiers are held in this chord.
    let modifiers: Modifiers

    /// The expected output from `processor.process(...)` at this step,
    /// or `nil` if we expect no output.
    let expectedOutput: HotKeyProcessor.Output?

    /// Whether we expect `processor.isMatched` after this step, or `nil` if we don't care.
    let expectedIsMatched: Bool?

    /// If we want to check the processor's exact `state`.
    /// This is optional; if `nil` we won't check it.
    let expectedState: HotKeyProcessor.State?

    init(
        time: TimeInterval,
        key: Key? = nil,
        modifiers: Modifiers = [],
        expectedOutput: HotKeyProcessor.Output? = nil,
        expectedIsMatched: Bool? = nil,
        expectedState: HotKeyProcessor.State? = nil
    ) {
        self.time = time
        self.key = key
        self.modifiers = modifiers
        self.expectedOutput = expectedOutput
        self.expectedIsMatched = expectedIsMatched
        self.expectedState = expectedState
    }
}

/// Replays `steps` against a fresh processor, scrubbing `\.date` to each step's timestamp.
///
/// Steps are replayed in the order given — they are authored chronologically, and a
/// non-stable sort would silently reorder the several scenarios that share a timestamp.
func runScenario(
    hotkey: HotKey,
    useDoubleTapOnly: Bool = false,
    doubleTapLockEnabled: Bool = true,
    steps: [ScenarioStep],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    var processor = withDependencies {
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    } operation: {
        HotKeyProcessor(
            hotkey: hotkey,
            useDoubleTapOnly: useDoubleTapOnly,
            doubleTapLockEnabled: doubleTapLockEnabled
        )
    }

    for step in steps {
        withDependencies {
            $0.date = .constant(Date(timeIntervalSince1970: step.time))
        } operation: {
            let event = KeyEvent(key: step.key, modifiers: step.modifiers)
            check(step, output: processor.process(keyEvent: event), processor, sourceLocation)
        }
    }
}

private func check(
    _ step: ScenarioStep,
    output: HotKeyProcessor.Output?,
    _ processor: HotKeyProcessor,
    _ sourceLocation: SourceLocation
) {
    #expect(
        output == step.expectedOutput,
        "\(step.time)s: expected output \(String(describing: step.expectedOutput)), got \(String(describing: output))",
        sourceLocation: sourceLocation
    )

    if let expectedIsMatched = step.expectedIsMatched {
        #expect(
            processor.isMatched == expectedIsMatched,
            "\(step.time)s: expected isMatched=\(expectedIsMatched), got \(processor.isMatched)",
            sourceLocation: sourceLocation
        )
    }

    if let expectedState = step.expectedState {
        #expect(
            processor.state == expectedState,
            "\(step.time)s: expected state=\(expectedState), got \(processor.state)",
            sourceLocation: sourceLocation
        )
    }
}
