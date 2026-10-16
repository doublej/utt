import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  baseline,
  consent,
  DOWNLOAD,
  describeKey,
  EXTENSION_ID,
  installManifest,
  Missing,
  manifest,
  parseLevel,
  parsePartial,
  parseTranscript,
} from "../src/utt"

const keys = { toggle: "ctrl+s", redo: "ctrl+y" }

describe("lanes", () => {
  test("a partial needs a sequence and text; speaking defaults to true", () => {
    expect(parsePartial('{"sequence":3,"text":"hi","speaking":false,"writtenAt":""}')).toEqual({
      sequence: 3,
      text: "hi",
      speaking: false,
    })
    expect(parsePartial('{"sequence":3,"text":"hi"}')?.speaking).toBe(true)
    expect(parsePartial('{"text":"hi"}')).toBeUndefined()
    expect(parsePartial("{half a fi")).toBeUndefined()
  })

  test("a level needs a sequence and a number; recording defaults to true", () => {
    expect(parseLevel('{"sequence":812,"level":0.083,"recording":false}')).toEqual({
      sequence: 812,
      level: 0.083,
      recording: false,
    })
    expect(parseLevel('{"sequence":1,"level":0.5}')?.recording).toBe(true)
    expect(parseLevel('{"sequence":1}')).toBeUndefined()
  })

  test("a transcript keeps only what the plugin uses", () => {
    expect(parseTranscript('{"sequence":12,"text":"Hello.","raw":"hello","stages":[]}')).toEqual({
      sequence: 12,
      text: "Hello.",
    })
  })
})

describe("keys", () => {
  test("described the way a person reads them", () => {
    expect(describeKey("ctrl+s")).toBe("Ctrl+S")
    expect(describeKey("ctrl+shift+s,f5")).toBe("Ctrl+Shift+S")
    expect(describeKey("<leader>v")).toBe("the leader key, then V")
  })
})

describe("the extension folder", () => {
  let support: string
  const previous = process.env.UTT_APPLICATION_SUPPORT

  beforeEach(() => {
    support = mkdtempSync(join(tmpdir(), "utt-opencode-"))
    process.env.UTT_APPLICATION_SUPPORT = support
  })

  afterEach(() => {
    rmSync(support, { recursive: true, force: true })
    if (previous === undefined) delete process.env.UTT_APPLICATION_SUPPORT
    else process.env.UTT_APPLICATION_SUPPORT = previous
  })

  test("no manifest on a Mac where utt never ran", () => {
    rmSync(support, { recursive: true, force: true })
    expect(installManifest(keys)).toBe(false)
  })

  test("the manifest is one utt accepts", () => {
    expect(installManifest(keys)).toBe(true)
    const written = JSON.parse(readFileSync(join(support, "extensions", `${EXTENSION_ID}.json`), "utf8"))
    expect(written).toEqual(manifest(keys))
    expect(written.id).toBe(EXTENSION_ID)
    expect(written.blurb.length).toBeLessThanOrEqual(120)
    expect(written.description.length).toBeLessThanOrEqual(400)
    expect(written.description).toContain("Ctrl+S")
    // Both, or utt treats `for=` as an ordinary dictation.
    expect(written.ownsDictation).toBe(true)
    expect(written.wantsTranscripts).toBe(true)
  })

  test("baseline and consent read what utt wrote", () => {
    const extensions = join(support, "extensions")
    mkdirSync(extensions)
    expect(baseline()).toEqual({ partial: 0, transcript: 0, level: 0 })
    expect(consent()).toBe("pending")
    writeFileSync(join(extensions, "opencode.partial.json"), '{"sequence":41,"text":"x","speaking":false}')
    writeFileSync(join(extensions, "opencode.transcript.json"), '{"sequence":9,"text":"X."}')
    writeFileSync(join(extensions, "opencode.level.json"), '{"sequence":812,"level":0,"recording":false}')
    writeFileSync(join(extensions, "opencode.consent.json"), '{"decision":"approved","decidedAt":""}')
    expect(baseline()).toEqual({ partial: 41, transcript: 9, level: 812 })
    expect(consent()).toBe("approved")
  })
})

describe("Missing", () => {
  test("on a Mac it says where to get utt", () => {
    expect(new Missing("darwin").message).toContain(DOWNLOAD)
  })

  test("anywhere else it says utt is Mac-only", () => {
    expect(new Missing("linux").message).toContain("only on macOS")
  })
})
