import { type Editor, Region, type Span } from "./region"
import { type Baseline, type Level, Missing, type Partial, type Transcript, type Verb } from "./utt"

/**
 * - `recording` — utt is listening; each partial replaces the dictated stretch.
 * - `finishing` — the microphone has closed; waiting for the transcript.
 */
export type Phase = "idle" | "recording" | "finishing"

export interface Deps {
  send(verb: Verb): Promise<void>
  /** Whichever text field has the cursor — normally the prompt. */
  editor(): Editor | undefined
  partial(): Promise<Partial | undefined>
  transcript(): Promise<Transcript | undefined>
  level(): Promise<Level | undefined>
  baseline(): Baseline
  /** The level to draw, or undefined for no meter. */
  meter(level: number | undefined): void
  /** The speech model writing this dictation's transcript, or undefined for none to show. */
  model(name: string | undefined): void
  /** Draws `words` as not final yet; called with nothing, they are ordinary text again. */
  shade(editor?: Editor, words?: Span): void
  clearPrompt(): void
  say(message: string, variant?: "info" | "warning" | "error"): void
  /** One line per decision, never the words — what to read when a dictation went wrong. */
  trace(event: string): void
  now(): number
  sleep(ms: number): Promise<void>
}

export const WAIT = {
  /** utt answers every dictation of ours, with "" when nothing came of it; this only covers utt dying. */
  final: 30_000,
  /** Stopped before utt's first level write was read: long enough for its closing one to show up. */
  claim: 1_000,
  /** A recording nobody ever stopped. */
  recording: 15 * 60_000,
  /** utt cancels on one action and starts on the next; a breath between keeps them in order. */
  restart: 250,
}

/**
 * One dictation into the prompt, from the key going down to the transcript landing.
 *
 * utt hands a dictation it was started for (`utt://start?for=opencode`) to this
 * plugin alone: no panels of its own, no paste. The level, the words as they are
 * heard and the transcript arrive as files, and the plugin puts the words into
 * the prompt itself. The first level write is how it knows the dictation is
 * ours; until one comes — an older utt, or one that has not been approved — utt
 * shows and pastes the dictation itself, and the plugin stays out of the prompt.
 *
 * No key ever waits on utt. Pressed while a transcript is on its way, the
 * dictate key starts the next take, and Esc drops the one in flight.
 */
export class Dictation {
  private current: Phase = "idle"
  private region?: Region
  private seen: Baseline = { partial: 0, transcript: 0, level: 0 }
  private owned = false
  private deadline = 0
  private readonly listeners = new Set<(phase: Phase) => void>()

  constructor(private readonly deps: Deps) {}

  get phase(): Phase {
    return this.current
  }

  onChange(listener: (phase: Phase) => void): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  async toggle(): Promise<void> {
    if (this.current === "recording") return this.stop()
    // From `finishing`: utt drops a transcription in flight when a recording starts,
    // so the take given up on keeps its live words and nothing more arrives for it.
    return this.start()
  }

  /** Clears the prompt and starts again — for a take that came out wrong. */
  async redo(): Promise<void> {
    if (this.current !== "idle") {
      await this.cancel()
      await this.deps.sleep(WAIT.restart)
    }
    this.deps.clearPrompt()
    await this.start()
  }

  /** Takes the words back out, and tells utt to drop the recording or the transcription in flight. */
  async cancel(): Promise<void> {
    if (this.current === "idle") return
    this.deps.trace(`cancel while ${this.current}`)
    this.region?.set("")
    this.enter("idle")
    await this.send("cancel")
  }

  /** Reads the lanes once. Called on a short timer while a dictation is open. */
  async tick(): Promise<void> {
    if (!this.open) return
    const [level, partial, transcript] = await Promise.all([
      this.deps.level(),
      this.deps.partial(),
      this.deps.transcript(),
    ])
    if (!this.open) return
    if (this.current === "recording") this.place()
    if (level && level.sequence > this.seen.level) {
      this.seen.level = level.sequence
      this.metered(level)
    }
    if (partial && partial.sequence > this.seen.partial) {
      this.seen.partial = partial.sequence
      if (this.owned && this.current === "recording") this.hear(partial.text.trim())
    }
    if (transcript && transcript.sequence > this.seen.transcript) {
      this.seen.transcript = transcript.sequence
      if (this.owned && this.current === "finishing") this.land(transcript.text)
    }
    this.expireIfLate()
  }

  private get open(): boolean {
    return this.current !== "idle"
  }

  private async start() {
    this.seen = this.deps.baseline()
    // A take given up on mid-transcript keeps its words, as ordinary text.
    this.deps.shade()
    this.region = undefined
    this.owned = false
    this.deps.trace(`start (after level #${this.seen.level}, transcript #${this.seen.transcript})`)
    this.enter("recording", WAIT.recording)
    await this.send("start")
  }

  private async stop() {
    this.deps.trace("stop")
    this.finish()
    await this.send("stop")
  }

  /**
   * The transcript is on its way. Not known to be ours yet, it waits only long
   * enough for utt's closing level write: without one, utt is showing and pasting
   * this dictation itself.
   */
  private finish() {
    this.enter("finishing", this.owned ? WAIT.final : WAIT.claim)
  }

  private metered(level: Level) {
    if (!this.owned) {
      this.owned = true
      this.deps.trace("utt handed the dictation over")
      if (this.current === "finishing") this.deadline = this.deps.now() + WAIT.final
    }
    this.deps.meter(level.recording && this.current === "recording" ? level.level : undefined)
    if (level.model) this.deps.model(level.model)
    // The person's own key in utt ended it.
    if (!level.recording && this.current === "recording") this.finish()
  }

  /**
   * The stretch is placed on the first tick, not at the key: started from the
   * command palette, the palette's own field still has the cursor when the
   * command runs, and the prompt only gets it back once the palette has closed.
   */
  private place(): Region | undefined {
    if (!this.region) {
      const editor = this.deps.editor()
      if (editor) this.region = new Region(editor)
    }
    return this.region
  }

  /** The live words, drawn as not final yet; edited away, they are left alone. */
  private hear(words: string) {
    const region = this.place()
    if (region?.set(words)) this.deps.shade(region.editor, region.words)
    else this.deps.shade()
  }

  /** The transcript over the live words, or at the cursor if they were edited away. "" is utt saying nothing came of it. */
  private land(text: string) {
    const words = text.trim()
    this.deps.trace(words ? `land len=${words.length}` : "utt sent nothing back")
    this.deps.shade()
    if (!this.place()?.set(words) && words) {
      const editor = this.deps.editor()
      if (editor) editor.insertText(words)
      else this.deps.say(`Nowhere to put it: ${words}`, "warning")
    }
    this.enter("idle")
  }

  private expireIfLate() {
    if (!this.open || this.deps.now() <= this.deadline) return
    if (!this.owned && this.current === "finishing") {
      this.deps.trace("not ours: utt shows and pastes it itself")
      return this.enter("idle")
    }
    this.deps.trace(`gave up while ${this.current}`)
    this.deps.say(
      this.current === "finishing" ? "utt sent no transcript back" : "Stopped waiting on a recording that never ended",
      "warning",
    )
    this.enter("idle")
  }

  private async send(verb: Verb) {
    try {
      await this.deps.send(verb)
    } catch (cause) {
      if (verb === "start") this.region?.set("")
      this.enter("idle")
      if (cause instanceof Missing) return this.deps.say(cause.message, "warning")
      this.deps.say(`Could not reach utt: ${cause instanceof Error ? cause.message : String(cause)}`, "error")
    }
  }

  private enter(phase: Phase, wait = 0) {
    this.deadline = this.deps.now() + wait
    if (phase !== "recording") this.deps.meter(undefined)
    if (phase === "idle") {
      this.deps.shade()
      this.deps.model(undefined)
      this.region = undefined
    }
    if (phase === this.current) return
    this.current = phase
    for (const listener of this.listeners) listener(phase)
  }
}
