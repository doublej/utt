import { describe, expect, test } from "bun:test"
import { Region } from "../src/region"
import { FakeEditor } from "./fake-editor"

describe("Region", () => {
  test("each update replaces the last one whole", () => {
    const editor = new FakeEditor()
    const region = new Region(editor)
    region.set("hel")
    region.set("hello wor")
    region.set("Hello, world.")
    expect(editor.text).toBe("Hello, world.")
    expect(editor.cursorOffset).toBe(editor.text.length)
  })

  test("keeps what was typed before it and spaces itself off", () => {
    const editor = new FakeEditor("fix this")
    const region = new Region(editor)
    region.set("in the parser")
    expect(editor.text).toBe("fix this in the parser")
  })

  test("lands mid-prompt without gluing onto the next word", () => {
    const editor = new FakeEditor("fix please", 4)
    const region = new Region(editor)
    region.set("it")
    region.set("it now")
    expect(editor.text).toBe("fix it now please")
  })

  test("an empty update takes the words back out, padding included", () => {
    const editor = new FakeEditor("fix this")
    const region = new Region(editor)
    region.set("now")
    region.set("")
    expect(editor.text).toBe("fix this")
    expect(region.filled).toBe(false)
  })

  test("refuses once someone has typed into it", () => {
    const editor = new FakeEditor()
    const region = new Region(editor)
    region.set("hello")
    editor.cursorOffset = 2
    editor.type("X")
    expect(region.set("hello world")).toBe(false)
    expect(editor.text).toBe("heXllo")
  })

  test("refuses once the prompt was cleared", () => {
    const editor = new FakeEditor()
    const region = new Region(editor)
    region.set("hello")
    editor.text = ""
    editor.cursorOffset = 0
    expect(region.set("hello world")).toBe(false)
    expect(editor.text).toBe("")
  })

  test("refuses a destroyed editor", () => {
    const editor = new FakeEditor()
    const region = new Region(editor)
    editor.isDestroyed = true
    expect(region.set("hello")).toBe(false)
  })
})
