import type { Editor } from "../src/region"

/** A one-line stand-in for OpenTUI's editor: offsets are string indices. */
export class FakeEditor implements Editor {
  isDestroyed = false
  private selection?: [number, number]

  constructor(
    public text = "",
    public cursorOffset = text.length,
  ) {}

  setSelection(start: number, end: number) {
    this.selection = [start, end]
  }

  insertText(text: string) {
    this.deleteSelection()
    this.text = this.text.slice(0, this.cursorOffset) + text + this.text.slice(this.cursorOffset)
    this.cursorOffset += text.length
  }

  deleteSelection(): boolean {
    if (!this.selection) return false
    const [start, end] = this.selection
    this.text = this.text.slice(0, start) + this.text.slice(end)
    this.cursorOffset = start
    this.selection = undefined
    return true
  }

  getTextRange(start: number, end: number): string {
    return this.text.slice(Math.max(0, start), Math.max(0, end))
  }

  /** The person typing, at the cursor. */
  type(text: string) {
    this.insertText(text)
  }

  /** Every edit made from outside the plugin starts from a clean cursor. */
  reset(text: string) {
    this.text = text
    this.cursorOffset = text.length
  }
}
