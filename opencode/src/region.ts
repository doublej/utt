/**
 * The slice of OpenTUI's `EditBufferRenderable` a dictation needs. Offsets are the
 * editor's own units — they are only ever read back from `cursorOffset`, never
 * computed from a string's length, so wide characters cannot skew them.
 */
export interface Editor {
  readonly isDestroyed: boolean
  readonly cursorOffset: number
  setSelection(start: number, end: number): void
  insertText(text: string): void
  deleteSelection(): boolean
  getTextRange(start: number, end: number): string
}

/** A stretch of an editor, in its own offsets. */
export interface Span {
  start: number
  end: number
}

/**
 * The stretch of the prompt one dictation owns: empty at the cursor when it
 * starts, then whatever utt last heard. Each update replaces the stretch whole,
 * because the recogniser revises words it already said.
 *
 * It only ever touches text it can prove is still its own. Type into it, submit
 * it or clear it, and `set` refuses rather than overwriting what you did.
 */
export class Region {
  private end: number
  private text = ""
  /** A space where the words would otherwise run into the text around them. */
  private readonly lead: string
  private readonly trail: string

  constructor(
    readonly editor: Editor,
    private readonly start = editor.cursorOffset,
  ) {
    this.end = start
    this.lead = start > 0 && /\S/.test(editor.getTextRange(start - 1, start)) ? " " : ""
    this.trail = /\S/.test(editor.getTextRange(start, start + 1)) ? " " : ""
  }

  get filled(): boolean {
    return this.text !== ""
  }

  /** Where the words themselves sit, without the spaces around them. Undefined while empty. */
  get words(): Span | undefined {
    if (!this.text) return
    return { start: this.start + this.lead.length, end: this.end - this.trail.length }
  }

  get intact(): boolean {
    return !this.editor.isDestroyed && this.editor.getTextRange(this.start, this.end) === this.text
  }

  /** True when the stretch now reads `words`; false, and nothing touched, when it is no longer ours. */
  set(words: string): boolean {
    if (!this.intact) return false
    const next = words ? this.lead + words + this.trail : ""
    if (next === this.text) return true
    if (this.end > this.start) this.editor.setSelection(this.start, this.end)
    if (next) this.editor.insertText(next)
    else if (this.end > this.start) this.editor.deleteSelection()
    this.end = this.editor.cursorOffset
    this.text = next
    return true
  }
}
