import { describe, expect, test } from "bun:test"
import { Dictation, WAIT } from "../src/dictation"
import { DOWNLOAD, type Level, Missing, type Partial, type Transcript, type Verb } from "../src/utt"
import { FakeEditor } from "./fake-editor"

function harness(editor: FakeEditor | null = new FakeEditor()) {
  const lanes: { partial?: Partial; transcript?: Transcript; level?: Level } = {
    partial: { sequence: 40, text: "an older recording", speaking: false },
    transcript: { sequence: 7, text: "An older transcript." },
    level: { sequence: 900, level: 0, recording: false },
  }
  const sent: Verb[] = []
  const said: string[] = []
  const meter: (number | undefined)[] = []
  let model: string | undefined
  /** What is drawn as not final yet, read back from the editor: undefined is nothing. */
  let shaded: string | undefined
  let clock = 1_000
  let failing = false
  const dictation = new Dictation({
    send: async (verb) => {
      if (failing) throw new Missing("darwin")
      sent.push(verb)
    },
    editor: () => editor ?? undefined,
    partial: async () => lanes.partial,
    transcript: async () => lanes.transcript,
    level: async () => lanes.level,
    baseline: () => ({
      partial: lanes.partial?.sequence ?? 0,
      transcript: lanes.transcript?.sequence ?? 0,
      level: lanes.level?.sequence ?? 0,
    }),
    meter: (level) => void meter.push(level),
    model: (name) => {
      model = name
    },
    shade: (target, words) => {
      shaded = target && words ? target.getTextRange(words.start, words.end) : undefined
    },
    clearPrompt: () => editor?.reset(""),
    say: (message) => void said.push(message),
    trace: () => {},
    now: () => clock,
    sleep: async () => {},
  })
  const tick = (ms = 50) => {
    clock += ms
    return dictation.tick()
  }
  /** utt's level lane: what makes a dictation ours. */
  const level = (value: number, recording = true) => {
    const model = "Parakeet Standard"
    lanes.level = { sequence: lanes.level!.sequence + 1, level: value, recording, model }
    return tick()
  }
  const hear = (text: string, speaking = true) => {
    lanes.partial = { sequence: lanes.partial!.sequence + 1, text, speaking }
    return tick()
  }
  const transcribe = (text: string) => {
    lanes.transcript = { sequence: lanes.transcript!.sequence + 1, text }
    return tick()
  }
  /** A dictation utt has handed to the plugin, with the mic open. */
  const begin = async () => {
    await dictation.toggle()
    await level(0.1)
  }
  return {
    dictation,
    editor: editor!,
    sent,
    said,
    meter,
    model: () => model,
    shaded: () => shaded,
    tick,
    level,
    hear,
    transcribe,
    begin,
    fail: () => (failing = true),
  }
}

describe("a dictation utt hands over", () => {
  test("live words fill the prompt, the transcript replaces them", async () => {
    const { dictation, editor, sent, hear, transcribe, begin } = harness()
    await begin()
    await hear("so the")
    await hear("so the parser fails")
    expect(editor.text).toBe("so the parser fails")

    await dictation.toggle()
    expect(dictation.phase).toBe("finishing")
    await transcribe("So the parser fails.")
    expect(editor.text).toBe("So the parser fails.")
    expect(dictation.phase).toBe("idle")
    expect(sent).toEqual(["start", "stop"])
  })

  test("live words are drawn as not final until the transcript replaces them", async () => {
    const { dictation, shaded, hear, transcribe, begin } = harness(new FakeEditor("review"))
    await begin()
    await hear("the diff")
    expect(shaded()).toBe("the diff")
    await dictation.toggle()
    expect(shaded()).toBe("the diff")
    await transcribe("the diff.")
    expect(shaded()).toBeUndefined()
  })

  test("words thrown away or given up on stop being drawn as live", async () => {
    const { dictation, shaded, hear, level, begin } = harness()
    await begin()
    await hear("never mind")
    await dictation.cancel()
    expect(shaded()).toBeUndefined()

    await begin()
    await hear("first part")
    await dictation.toggle()
    await dictation.toggle()
    expect(shaded()).toBeUndefined()
    await level(0.2)
    await hear("second")
    expect(shaded()).toBe("second")
  })

  test("words already in the prompt stay", async () => {
    const { dictation, editor, hear, transcribe, begin } = harness(new FakeEditor("review"))
    await begin()
    await hear("the diff")
    await dictation.toggle()
    await transcribe("the diff.")
    expect(editor.text).toBe("review the diff.")
  })

  test("names utt's speech model while the dictation is open", async () => {
    const { dictation, model, transcribe, begin } = harness()
    await begin()
    expect(model()).toBe("Parakeet Standard")
    await dictation.toggle()
    expect(model()).toBe("Parakeet Standard")
    await transcribe("Done.")
    expect(model()).toBeUndefined()
  })

  test("the meter follows utt's level while recording and goes when the mic closes", async () => {
    const { dictation, meter, level, begin } = harness()
    await begin()
    await level(0.4)
    expect(meter.at(-1)).toBe(0.4)
    await dictation.toggle()
    expect(meter.at(-1)).toBeUndefined()
    await level(0, false)
    expect(meter.at(-1)).toBeUndefined()
  })

  test("utt's own key ending it is noticed through the closing level write", async () => {
    const { dictation, level, begin } = harness()
    await begin()
    await level(0, false)
    expect(dictation.phase).toBe("finishing")
  })

  test("an empty transcript is utt saying nothing came of it: the live words go", async () => {
    const { dictation, editor, hear, transcribe, begin } = harness(new FakeEditor("keep"))
    await begin()
    await hear("mumble")
    await dictation.toggle()
    await transcribe("")
    expect(editor.text).toBe("keep")
    expect(dictation.phase).toBe("idle")
  })

  test("leaves earlier lanes alone", async () => {
    const { dictation, editor, tick, begin } = harness()
    await begin()
    await tick()
    expect(editor.text).toBe("")
    expect(dictation.phase).toBe("recording")
  })

  test("typing over the live words: the transcript still lands, once, at the cursor", async () => {
    const { dictation, editor, hear, transcribe, begin } = harness()
    await begin()
    await hear("hello")
    editor.reset("something else")
    await hear("hello world")
    expect(editor.text).toBe("something else")
    await dictation.toggle()
    await transcribe(" Hello world.")
    expect(editor.text).toBe("something elseHello world.")
  })
})

describe("a dictation utt keeps (older utt, or not approved)", () => {
  test("no level writes: the plugin stays out of the prompt and lets utt paste", async () => {
    const { dictation, editor, hear, tick, transcribe } = harness()
    await dictation.toggle()
    await hear("not ours")
    expect(editor.text).toBe("")
    await dictation.toggle()
    await tick(WAIT.claim + 1)
    expect(dictation.phase).toBe("idle")
    await transcribe("Not ours.")
    expect(editor.text).toBe("")
  })

  test("stopped before the first level write was read: the closing one still claims it", async () => {
    const { dictation, editor, level, transcribe } = harness()
    await dictation.toggle()
    await dictation.toggle()
    await level(0, false)
    expect(dictation.phase).toBe("finishing")
    await transcribe("Quick.")
    expect(editor.text).toBe("Quick.")
  })
})

describe("nothing waits on utt", () => {
  test("the dictate key during transcribing starts the next take, keeping the words", async () => {
    const { dictation, editor, sent, hear, level, begin } = harness()
    await begin()
    await hear("first part")
    await dictation.toggle()
    await dictation.toggle()
    expect(dictation.phase).toBe("recording")
    expect(sent).toEqual(["start", "stop", "start"])
    await level(0.2)
    await hear("second part")
    expect(editor.text).toBe("first part second part")
  })

  test("Esc while recording takes the words out and cancels utt", async () => {
    const { dictation, editor, sent, hear, begin } = harness(new FakeEditor("keep"))
    await begin()
    await hear("throw this away")
    await dictation.cancel()
    expect(editor.text).toBe("keep")
    expect(sent).toEqual(["start", "cancel"])
    expect(dictation.phase).toBe("idle")
  })

  test("Esc while transcribing frees the keys at once and tells utt to drop it", async () => {
    const { dictation, editor, sent, hear, begin } = harness()
    await begin()
    await hear("never mind")
    await dictation.toggle()
    await dictation.cancel()
    expect(dictation.phase).toBe("idle")
    expect(editor.text).toBe("")
    expect(sent).toEqual(["start", "stop", "cancel"])
  })

  test("redo while transcribing clears and records again", async () => {
    const { dictation, editor, sent, hear, level, begin } = harness()
    await begin()
    await hear("wrong")
    await dictation.toggle()
    await dictation.redo()
    expect(sent).toEqual(["start", "stop", "cancel", "start"])
    expect(editor.text).toBe("")
    await level(0.2)
    await hear("right")
    expect(editor.text).toBe("right")
  })

  test("redo mid-recording cancels the take first", async () => {
    const { dictation, editor, sent, hear, level, begin } = harness()
    await begin()
    await hear("wrong")
    await dictation.redo()
    expect(sent).toEqual(["start", "cancel", "start"])
    expect(editor.text).toBe("")
    await level(0.2)
    await hear("right")
    expect(editor.text).toBe("right")
  })

  test("redo after a finished take", async () => {
    const { dictation, editor, sent, hear, transcribe, begin } = harness()
    await begin()
    await hear("first take")
    await dictation.toggle()
    await transcribe("First take.")
    await dictation.redo()
    expect(editor.text).toBe("")
    expect(dictation.phase).toBe("recording")
    expect(sent).toEqual(["start", "stop", "start"])
  })

  test("a transcript that never comes is given up on, keeping the live words", async () => {
    const { dictation, editor, said, hear, tick, begin } = harness()
    await begin()
    await hear("half a thought")
    await dictation.toggle()
    await tick(WAIT.final + 1)
    expect(dictation.phase).toBe("idle")
    expect(editor.text).toBe("half a thought")
    expect(said[0]).toContain("no transcript")
  })
})

test("utt missing: nothing changes and it says why", async () => {
  const { dictation, said, fail } = harness()
  fail()
  await dictation.toggle()
  expect(dictation.phase).toBe("idle")
  expect(said[0]).toContain("Dictation needs utt")
  expect(said[0]).toContain(DOWNLOAD)
})

test("no text field focused: the transcript is shown instead of lost", async () => {
  const { dictation, said, level, transcribe } = harness(null)
  await dictation.toggle()
  await level(0.1)
  await dictation.toggle()
  await transcribe("Hello.")
  expect(said[0]).toContain("Hello.")
})
