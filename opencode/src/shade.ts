import type { ExtmarksController, StyleDefinitionInput, SyntaxStyle } from "@opentui/core"
import type { Editor, Span } from "./region"

/** What OpenTUI's textarea has beyond the editor slice: styles, and extmarks to hang one on. */
interface Styled extends Editor {
  readonly syntaxStyle?: SyntaxStyle | null
  readonly extmarks?: ExtmarksController
}

const NAME = "utt.live"

/**
 * Draws the live words in a style of their own until the transcript replaces
 * them. An extmark, not a bare highlight: the textarea rebuilds every highlight
 * from its extmarks on each change, so a plain one is gone at the next keystroke.
 * Only one stretch is ever shaded, so every call first takes the last one down.
 */
export function shader(style: () => StyleDefinitionInput) {
  let current: { editor: Styled; id: number } | undefined
  return (editor?: Editor, words?: Span) => {
    if (current && !current.editor.isDestroyed) current.editor.extmarks?.delete(current.id)
    current = undefined
    const target = editor as Styled | undefined
    if (!target || !words || words.end <= words.start || target.isDestroyed) return
    const { extmarks, syntaxStyle } = target
    if (!extmarks || !syntaxStyle) return
    const styleId = syntaxStyle.getStyleId(NAME) ?? syntaxStyle.registerStyle(NAME, style())
    const typeId = extmarks.getTypeId(NAME) ?? extmarks.registerType(NAME)
    current = { editor: target, id: extmarks.create({ start: words.start, end: words.end, styleId, typeId }) }
  }
}
