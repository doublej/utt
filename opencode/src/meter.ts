/** Which part of the scale a lit segment sits in, as utt's own meters colour it. */
export type Zone = "low" | "mid" | "peak"

/**
 * utt's meter, in segments: the peak on a dB scale floored at -60, because speech
 * sits around -30 to -10 dB and a linear bar would leave it in the first few
 * percent. Unlit segments are `undefined`. Same zones as utt's compact meter:
 * green to 64%, yellow to 86%, red above.
 */
export function segments(level: number, count = 12): (Zone | undefined)[] {
  const decibels = level > 0.001 ? Math.max(-60, 20 * Math.log10(level)) : -60
  const lit = Math.floor(Math.min(1, Math.max(0, (decibels + 60) / 60)) * count)
  return Array.from({ length: count }, (_, index) => {
    if (index >= lit) return undefined
    if (index >= Math.floor(count * 0.86)) return "peak"
    if (index >= Math.floor(count * 0.64)) return "mid"
    return "low"
  })
}
