import { expect, test } from "bun:test"
import { segments } from "../src/meter"

const lit = (level: number) => segments(level).filter(Boolean).length

test("silence lights nothing, full scale lights everything", () => {
  expect(lit(0)).toBe(0)
  expect(lit(1)).toBe(12)
})

test("speech lands mid-scale on the dB scale, not in the first segment", () => {
  // -20 dBFS: two thirds of the way up a -60…0 scale.
  expect(lit(0.1)).toBe(8)
})

test("zones run green, yellow, red from the bottom up", () => {
  expect(segments(1)).toEqual([
    "low", "low", "low", "low", "low", "low", "low",
    "mid", "mid", "mid",
    "peak", "peak",
  ])
})
