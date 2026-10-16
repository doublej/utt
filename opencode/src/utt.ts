/**
 * Everything this plugin knows about utt goes through here: the extension files
 * utt writes into Application Support, and the `utt://` verbs it answers. The
 * same two doors the Raycast extension uses — no API, no socket, and never
 * utt's own settings.json.
 */
import { execFile } from "node:child_process"
import { appendFileSync, existsSync, mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

export const EXTENSION_ID = "opencode"

/** `UTT_APPLICATION_SUPPORT` is utt's own override, so a test run and the app agree. */
export function supportDir(env: Record<string, string | undefined> = process.env): string {
  return env.UTT_APPLICATION_SUPPORT ?? join(homedir(), "Library", "Application Support", "dev.jurrejan.utt")
}

const lane = (suffix: string) => join(supportDir(), "extensions", `${EXTENSION_ID}.${suffix}`)

/** `<id>.partial.json`: the words heard so far this recording, rewritten whole. */
export interface Partial {
  sequence: number
  text: string
  /** False on exactly one write per recording: the key has come up. */
  speaking: boolean
}

/** `<id>.transcript.json`: the newest finished transcript, the one utt pasted. */
export interface Transcript {
  sequence: number
  text: string
}

/** `<id>.level.json`: the microphone, ~20 times a second, during a dictation that is ours. */
export interface Level {
  sequence: number
  /** Peak amplitude, 0...1, linear. */
  level: number
  /** False on exactly one write per dictation: the microphone has closed. */
  recording: boolean
  /** The speech model that will write the transcript, as utt's picker names it. */
  model?: string
}

export type Consent = "approved" | "disabled" | "pending"

export function parsePartial(raw: string): Partial | undefined {
  const value = parse(raw)
  if (typeof value?.sequence !== "number" || typeof value.text !== "string") return
  return { sequence: value.sequence, text: value.text, speaking: value.speaking !== false }
}

export function parseTranscript(raw: string): Transcript | undefined {
  const value = parse(raw)
  if (typeof value?.sequence !== "number" || typeof value.text !== "string") return
  return { sequence: value.sequence, text: value.text }
}

export function parseLevel(raw: string): Level | undefined {
  const value = parse(raw)
  if (typeof value?.sequence !== "number" || typeof value.level !== "number") return
  const model = typeof value.model === "string" && value.model ? value.model : undefined
  return { sequence: value.sequence, level: value.level, recording: value.recording !== false, model }
}

/** A record utt cannot read is `pending`, the same way utt reads it. */
export function parseConsent(raw: string | undefined): Consent {
  const decision = raw === undefined ? undefined : parse(raw)?.decision
  return decision === "approved" || decision === "disabled" ? decision : "pending"
}

function parse(raw: string): Record<string, unknown> | undefined {
  try {
    const value: unknown = JSON.parse(raw)
    return value && typeof value === "object" ? (value as Record<string, unknown>) : undefined
  } catch {
    return
  }
}

const readLane = (suffix: string) => readFile(lane(suffix), "utf8").catch(() => undefined)

function readLaneSync(suffix: string): string | undefined {
  try {
    return readFileSync(lane(suffix), "utf8")
  } catch {
    return
  }
}

export const readPartial = async () => {
  const raw = await readLane("partial.json")
  return raw === undefined ? undefined : parsePartial(raw)
}

export const readTranscript = async () => {
  const raw = await readLane("transcript.json")
  return raw === undefined ? undefined : parseTranscript(raw)
}

export const readLevel = async () => {
  const raw = await readLane("level.json")
  return raw === undefined ? undefined : parseLevel(raw)
}

export interface Baseline {
  partial: number
  transcript: number
  level: number
}

/** Where every lane stands right now, so a dictation only acts on what comes after it. */
export function baseline(): Baseline {
  const sequence = (suffix: string, parse: (raw: string) => { sequence: number } | undefined) => {
    const raw = readLaneSync(suffix)
    return (raw && parse(raw)?.sequence) || 0
  }
  return {
    partial: sequence("partial.json", parsePartial),
    transcript: sequence("transcript.json", parseTranscript),
    level: sequence("level.json", parseLevel),
  }
}

export const consent = () => parseConsent(readLaneSync("consent.json"))

export interface Keys {
  toggle: string
  redo: string
}

/** `ctrl+s` → `Ctrl+S`, `<leader>v` → `the leader key, then V`. The first of several bindings. */
export function describeKey(binding: string): string {
  const first = binding.split(",")[0]!.trim()
  const chord = (text: string) =>
    text
      .split("+")
      .map((part) => ({ ctrl: "Ctrl", shift: "Shift", alt: "Option", super: "Cmd", escape: "Esc" })[part] ?? part.toUpperCase())
      .join("+")
  const leader = first.match(/^<leader>(.+)$/)
  return leader ? `the leader key, then ${chord(leader[1]!)}` : chord(first)
}

/** Read by utt's Extensions page, so it is written for the person using it. */
export function manifest(keys: Keys) {
  return {
    id: EXTENSION_ID,
    name: "OpenCode",
    blurb: "Dictate into OpenCode's prompt and watch the words land while you speak.",
    description:
      `Press ${describeKey(keys.toggle)} in OpenCode to start talking, and again to stop. OpenCode shows ` +
      "the dictation itself: a level meter, the words as utt hears them, then the finished transcript in " +
      `their place, ready to send. ${describeKey(keys.redo)} clears the prompt and starts over; Esc throws ` +
      'a dictation away. Words only appear while you speak if "Show words while you speak" is on.',
    repository: "https://github.com/doublej/utt",
    systemImage: "terminal",
    wantsPartials: true,
    wantsTranscripts: true,
    ownsDictation: true,
  }
}

/**
 * Written at every start-up, as utt asks, and only once utt has run on this Mac —
 * an install that never had utt should not grow its folders. Atomic: the temporary
 * name does not end in `.json`, so utt's scan never reads half a manifest.
 */
export function installManifest(keys: Keys): boolean {
  if (!existsSync(supportDir())) return false
  const path = lane("json")
  const next = `${JSON.stringify(manifest(keys), null, 2)}\n`
  if (readLaneSync("json") === next) return true
  mkdirSync(join(supportDir(), "extensions"), { recursive: true })
  const temporary = `${path}.${process.pid}.tmp`
  writeFileSync(temporary, next)
  renameSync(temporary, path)
  return true
}

export type Verb = "start" | "stop" | "cancel"

/**
 * Always `open -g`, so this terminal stays in front. `start` asks for the
 * dictation to be ours (`for=`): utt then shows none of its own panels and pastes
 * nothing. Unapproved, or an older utt, and it is an ordinary dictation instead.
 */
export const send = (verb: Verb) =>
  open(["-g", verb === "start" ? `utt://start?for=${EXTENSION_ID}` : `utt://${verb}`])

/** utt's window, on this extension's page, where the Approve button is. Never mid-dictation. */
export const showPage = () => open([`utt://show?section=${EXTENSION_ID}`])

function open(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    execFile("open", args, (error, _stdout, stderr) => {
      if (!error) return resolve()
      const reason = String(stderr).trim()
      reject(new Error(reason.includes("No application") ? "utt is not installed" : reason || error.message))
    })
  })
}

const LOG = join(homedir(), "Library", "Logs", "utt-opencode.log")

/** Appends one line per event, started fresh past 512 KB. It never holds the words. */
export function logger(path = LOG): (event: string) => void {
  try {
    if (statSync(path).size > 512 * 1024) writeFileSync(path, "")
  } catch {}
  return (event) => {
    try {
      appendFileSync(path, `${new Date().toISOString()} ${process.pid} ${event}\n`)
    } catch {}
  }
}
