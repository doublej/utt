import { Plugin } from "@opencode/plugin/tui"
import type { Context, ToastVariant } from "@opencode/plugin/tui/context"
import { createSignal, For, Show } from "solid-js"
import { Dictation, type Phase } from "./dictation"
import { segments, type Zone } from "./meter"
import { shader } from "./shade"
import * as utt from "./utt"

/** Fast enough that the meter and the words read as live, and only while a dictation is open. */
const POLL_MS = 50

/** Lowercase like OpenCode's own footer hints: `ctrl+s`, not `Ctrl+S`. */
const hint = (binding: string) => binding.split(",")[0]!.trim()

/**
 * utt's own LCD colours (`Palette.lcdGreen`, `lcdYellow`, `lcdRed`), not the
 * theme's: feedback colours are tuned to sit quietly in text, and a meter
 * has to read at a glance.
 */
const LCD: Record<Zone, string> = { low: "#9AD17A", mid: "#E0A022", peak: "#FF5A2E" }

/** utt's meter: lit segments in its green, yellow and red. */
function Meter(props: { context: Context; level: number }) {
  const unlit = () => props.context.theme.text.faint
  return (
    <text>
      <For each={segments(props.level)}>{(zone) => <span style={{ fg: zone ? LCD[zone] : unlit() }}>▮</span>}</For>
    </text>
  )
}

/** A key and what it does, the way OpenCode's own footer hints read. */
function Hint(props: { context: Context; keys: string; label: string }) {
  return (
    <text>
      <span style={{ fg: props.context.theme.text.base }}>{props.keys}</span>
      <span style={{ fg: props.context.theme.text.muted }}> {props.label}</span>
    </text>
  )
}

/**
 * The whole prompt footer while a dictation is open: the state, the level and the
 * speech model on the left, the keys that end it on the right. Token count, cost and the
 * command hints come back with the footer when it closes.
 */
function Footer(props: {
  context: Context
  phase: Phase
  level: number | undefined
  model: string | undefined
  keys: utt.Keys
}) {
  const theme = props.context.theme
  const recording = () => props.phase === "recording"
  return (
    <box flexDirection="row" flexGrow={1} justifyContent="space-between" gap={2}>
      <box flexDirection="row" gap={1}>
        <text fg={recording() ? LCD.peak : theme.text.muted}>{recording() ? "● listening" : "◌ transcribing"}</text>
        <Show when={props.level !== undefined}>
          <Meter context={props.context} level={props.level ?? 0} />
        </Show>
        <Show when={props.model}>
          <text fg={theme.text.muted}>{props.model}</text>
        </Show>
      </box>
      <box flexDirection="row" gap={2}>
        <Show when={recording()}>
          <Hint context={props.context} keys={hint(props.keys.toggle)} label="stop" />
        </Show>
        <Hint context={props.context} keys={hint(props.keys.redo)} label="redo" />
        <Hint context={props.context} keys="esc" label="drop" />
      </box>
    </box>
  )
}

export default Plugin.define({
  id: "utt.opencode",
  setup(context) {
    const keys: utt.Keys = {
      toggle: String(context.options.key ?? "ctrl+s"),
      redo: String(context.options.redoKey ?? "ctrl+y"),
    }
    const say = (message: string, variant: ToastVariant = "info") =>
      context.ui.toast.show({ title: "utt", message, variant })
    const register = () => {
      try {
        utt.installManifest(keys)
      } catch (cause) {
        say(`Could not register with utt: ${cause}`, "warning")
      }
    }
    register()
    const trace = utt.logger()

    const [phase, setPhase] = createSignal<Phase>("idle")
    const [level, setLevel] = createSignal<number | undefined>(undefined)
    const [model, setModel] = createSignal<string | undefined>(undefined)

    const dictation = new Dictation({
      send: utt.send,
      editor: () => context.renderer.currentFocusedEditor ?? undefined,
      partial: utt.readPartial,
      transcript: utt.readTranscript,
      level: utt.readLevel,
      baseline: utt.baseline,
      meter: setLevel,
      model: setModel,
      // Not final yet: the info colour, slanted. The transcript lands in the prompt's own.
      shade: shader(() => ({ fg: context.theme.text.feedback.info.base, italic: true })),
      clearPrompt: () => context.keymap.dispatch("prompt.clear"),
      say,
      trace,
      now: Date.now,
      sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    })

    let timer: ReturnType<typeof setInterval> | undefined
    let polling = false
    const poll = () => {
      if (polling) return
      polling = true
      dictation
        .tick()
        .catch((cause) => say(`Lost track of utt: ${cause}`, "error"))
        .finally(() => (polling = false))
    }
    // The footer is claimed only while a dictation is open: a replacement
    // suppresses everything under it, OpenCode's token count and hints included.
    let unslot: (() => void) | undefined
    const unwatch = dictation.onChange((next) => {
      setPhase(next)
      if (next !== "idle") {
        timer ??= setInterval(poll, POLL_MS)
        unslot ??= context.ui.slot({
          replace: "prompt.footer",
          render: () => <Footer context={context} phase={phase()} level={level()} model={model()} keys={keys} />,
        })
      } else {
        if (timer) timer = void clearInterval(timer)
        unslot = void unslot?.()
      }
    })

    // Until the person approves the extension in utt, utt shows and pastes the
    // dictation itself. The first press brings utt up on the page with the Approve
    // button instead of recording — utt in front would receive the paste. Once per
    // TUI: a second press dictates anyway, the ordinary way.
    let asked = false
    const ready = (): boolean => {
      if (dictation.phase !== "idle") return true
      register()
      if (asked || utt.consent() !== "pending") return true
      asked = true
      trace("not approved yet: showing utt's page")
      utt.showPage().catch((cause) => say(String(cause instanceof Error ? cause.message : cause), "error"))
      say(`Approve OpenCode in utt so it can show your dictation here, then press ${hint(keys.toggle)} again`)
      return false
    }

    context.keymap.layer(() => ({
      mode: "global",
      commands: [
        {
          id: "utt.dictate",
          title: "utt: dictate",
          description: "Start talking; press again to stop",
          group: "utt",
          bind: keys.toggle,
          palette: true,
          slash: { name: "dictate" },
          run: () => (ready() ? dictation.toggle() : undefined),
        },
        {
          id: "utt.redictate",
          title: "utt: clear and dictate again",
          description: "Empty the prompt and start a new take",
          group: "utt",
          bind: keys.redo,
          palette: true,
          slash: { name: "redictate" },
          run: () => (ready() ? dictation.redo() : undefined),
        },
      ],
    }))

    // Above the prompt's own Esc (interrupt) and Enter (submit), only while a
    // dictation is open. Enter waits for the transcript: sent any earlier, the
    // prompt would go out with words the transcript was about to replace.
    context.keymap.layer(() => ({
      mode: "global",
      priority: 100,
      enabled: phase() !== "idle",
      commands: [
        {
          id: "utt.cancel",
          title: "utt: throw this dictation away",
          group: "utt",
          bind: "escape",
          run: () => dictation.cancel(),
        },
        {
          id: "utt.hold",
          title: "utt: wait for the transcript before sending",
          group: "utt",
          bind: "return",
          run: () =>
            say(
              dictation.phase === "recording"
                ? `Still listening. ${hint(keys.toggle)} stops, then Enter sends`
                : "Still transcribing. Enter sends once the words are final",
              "warning",
            ),
        },
      ],
    }))

    return () => {
      // A reload or an exit mid-sentence must not leave utt's microphone open.
      if (dictation.phase === "recording") void utt.send("cancel").catch(() => {})
      if (timer) clearInterval(timer)
      unwatch()
      unslot?.()
    }
  },
})
