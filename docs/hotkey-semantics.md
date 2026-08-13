# utt HotKey Semantics

## Overview

utt uses a **threshold-based recording system** that behaves differently depending on whether your hotkey is **modifier-only** (e.g., Option) or **a regular hotkey** (e.g., Cmd+A).

The key insight: **Modifier-only hotkeys need protection from accidental triggers** (like quick Option taps for special characters), while regular hotkeys are inherently intentional.

---

## Quick Reference

### Modifier-Only Hotkeys (e.g., Option, Option+Command)

**Timeline: Press Option → START recording**

**Before 0.3s (< 0.3s):**
- Release → DISCARD (silent)
- Click → DISCARD (silent)
- Press A → DISCARD (silent)
- Add Shift → DISCARD (silent)
- All actions trigger silent discard

**After 0.3s (≥ 0.3s):**
- Release → STOP (transcribe)
- Click → NOP (ignore, keep recording)
- Press A → NOP (ignore, keep recording)
- Add Shift → NOP (ignore, keep recording)
- ESC → CANCEL (only way to stop)

**Key points:**
- **< 0.3s**: Everything except ESC triggers **silent discard** (no sound)
- **≥ 0.3s**: Only **ESC cancels** (with sound), everything else is **ignored**
- Recording continues until you release the modifier or press ESC

---

### Regular Hotkeys (e.g., Cmd+A, Option+K)

**Timeline: Press Cmd+A → START recording**

**Before 0.2s (< minimumKeyTime):**
- Release → DISCARD (silent)
- Click → DISCARD (silent)

**Between 0.2s - 1.0s:**
- Press different key (e.g., Cmd+B) → STOP (with sound)
- Add modifier (e.g., Shift) → STOP (with sound)

**After 1.0s (> 1.0s):**
- Press different key → NOP (ignore, keep recording)
- Add modifier → NOP (ignore, keep recording)
- Allows typing while recording

**Any time:**
- Release → STOP (transcribe if long enough)
- ESC → CANCEL

**Key points:**
- **< minimumKeyTime** (default 0.2s): **Silent discard**
- **0.2s - 1.0s**: Different key/modifier triggers **stop** (with sound)
- **> 1.0s**: Everything is **ignored** (allows typing while recording)
- Release or ESC always stops

---

## Constants & Thresholds

```swift
// For modifier-only hotkeys (system safety)
modifierOnlyMinimumDuration = 0.3s

// For all hotkeys (user-configurable)
minimumKeyTime = 0.2s (default)

// Other thresholds
doubleTapThreshold = 0.3s           // Max time between taps
pressAndHoldCancelThreshold = 1.0s  // For regular hotkeys only
```

### Effective Thresholds

The **actual threshold** used depends on the hotkey type:

```swift
// Modifier-only (e.g., Option)
effectiveThreshold = max(minimumKeyTime, 0.3s)
// User sets 0.1s → uses 0.3s
// User sets 0.5s → uses 0.5s

// Regular (e.g., Cmd+A)
effectiveThreshold = minimumKeyTime
// User sets 0.1s → uses 0.1s
// User sets 0.5s → uses 0.5s
```

---

## Recording Decision Matrix

When you **release** the hotkey, should we transcribe the recording?

**Modifier-only (Option):**
- Duration < 0.3s → Discard (silent)
- Duration ≥ 0.3s → Transcribe

**Regular (Cmd+A):**
- Duration < 0.2s (or < minimumKeyTime) → Discard (silent)
- Duration ≥ 0.2s (or ≥ minimumKeyTime) → Transcribe

*Note: minimumKeyTime can be adjusted by user, but modifier-only always enforces 0.3s minimum*

---

## Detailed Behaviors

### 1. Modifier-Only: Option

#### Scenario A: Quick tap (< 0.3s)
```
User: Hold Option (0.1s) → Release
      ↓
  START ────→ DISCARD (silent)
  
Result: No transcription, no sound
Why: Likely accidental (Option+Click, Option+A for special chars)
```

#### Scenario B: Hold and click (< 0.3s)
```
User: Hold Option (0.25s) → Click mouse
      ↓
  START ────→ DISCARD (silent)
  
Result: No transcription, no sound, click passes through
Why: Option+Click is for duplicating items in macOS
```

#### Scenario C: Hold and press A (< 0.3s)
```
User: Hold Option (0.2s) → Press A
      ↓
  START ────→ DISCARD (silent)
  
Result: No transcription, Option+A passes through to macOS
Why: Option+A might be for special character "å"
```

#### Scenario D: Hold longer (≥ 0.3s)
```
User: Hold Option (0.5s) → Release
      ↓
  START ───────────→ TRANSCRIBE
  
Result: Audio transcribed and pasted
```

#### Scenario E: Hold, then click (≥ 0.3s)
```
User: Hold Option (0.5s) → Click mouse
      ↓
  START ───────────→ (ignored, keeps recording)
  
Result: Recording continues, click passes through
Why: After 0.3s, we assume intentional recording
```

#### Scenario F: Hold, then add Shift (≥ 0.3s)
```
User: Hold Option (0.5s) → Add Shift
      ↓
  START ───────────→ (ignored, keeps recording)
  
Result: Recording continues, Option+Shift passes through
Why: User might be pressing Shift for capital letters while speaking
```

#### Scenario G: ESC cancels anytime
```
User: Hold Option (any duration) → Press ESC
      ↓
  START ───────────→ CANCEL (with sound)
  
Result: Recording cancelled, cancel sound plays
Why: ESC is explicit "I want to cancel" gesture
```

---

### 2. Regular Hotkey: Cmd+A

#### Scenario A: Quick tap (< 0.2s)
```
User: Hold Cmd+A (0.1s) → Release
      ↓
  START ────→ DISCARD (silent)
```

#### Scenario B: Press different key within 1s
```
User: Hold Cmd+A (0.5s) → Press Cmd+B
      ↓
  START ───────────→ STOP (with sound)
  
Result: Recording stopped, audio discarded
Why: User is likely using other Cmd shortcuts
```

#### Scenario C: Press different key after 1s
```
User: Hold Cmd+A (1.5s) → Press Cmd+B
      ↓
  START ───────────────────→ (ignored, keeps recording)
  
Result: Recording continues, Cmd+B passes through
Why: After 1s, assume user is transcribing while typing
```

#### Scenario D: Add modifier (< 1s)
```
User: Hold Cmd+A (0.5s) → Add Shift (Cmd+Shift+A)
      ↓
  START ───────────→ STOP (with sound)
  
Result: Recording stopped
Why: Cmd+Shift+A is likely a different command
```

---

### 3. Multi-Modifier: Option+Command

**Behaves like single modifier** (uses 0.3s threshold):

```
User: Hold Option+Command (0.25s) → Add Shift
      ↓
  START ────→ DISCARD (silent)

User: Hold Option+Command (0.5s) → Add Shift
      ↓
  START ───────────→ (ignored, keeps recording)
```

**Partial release = full release:**
```
User: Hold Option+Command → Release Command (keep Option)
      ↓
  START ───────────→ STOP
  
Result: Recording stopped and transcribed (if ≥ 0.3s)
Why: Releasing any part of the hotkey = release
```

---

## Double-Tap Lock

**Quick double-tap locks recording on** (hands-free mode)

### Timeline

```
0.0s: Tap hotkey ──────────→ START
0.1s: Release ─────────────→ STOP
0.2s: Tap again ───────────→ START
0.3s: Release ─────────────→ LOCK! (Δt = 0.2s < 0.3s)

Now recording is locked on:
- Release doesn't stop it
- Tap hotkey again to stop
- ESC also stops

5.0s: Tap hotkey ──────────→ STOP
```

### Sequence

1. **Tap 1** (t=0.0s) → START recording
2. **Release** (t=0.1s) → STOP (normal behavior)
3. **Tap 2** (t=0.2s, within 0.3s window) → START recording again
4. **Release** (t=0.3s, Δt=0.2s < 0.3s) → **LOCK!** (hands-free mode)
5. Recording continues until:
   - Tap hotkey again → STOP
   - Press ESC → STOP

### Rules

1. **Timing window**: 2nd tap must be within **0.3s** of 1st release
2. **Lock engages**: On **2nd release**, not 2nd press
3. **Exit lock**: Tap hotkey again OR press ESC
4. **Too slow**: If 2nd tap > 0.3s after 1st release, treated as new recording

---

## Output Types

- **`.discard`** (silent)
  - Stop recording
  - Discard audio
  - Pass keys through to macOS

- **`.stop`** (with stop sound)
  - Stop recording
  - Transcribe if duration ≥ threshold

- **`.cancel`** (with cancel sound)
  - Stop recording
  - Discard audio
  - Play cancel sound

---

## Key Interception

**When does utt intercept (block) key events from reaching other apps?**

**Key Interception Rules:**

- **Press modifier-only hotkey (Option)** → No (passes through)
- **Press regular hotkey (Cmd+A)** → Yes (blocked)
- **`.discard` output** → No (passes through) ← CRITICAL!
- **`.cancel` output** → Yes (blocked)
- **Mouse clicks** → Never intercepted (always pass through)

**Example:**
```
User: Press Option (0.2s) → Press A
      ↓
  START → DISCARD (passes through)
  
Result: utt discards recording silently
        macOS sees Option+A
        Special character dialog appears ✅
```

---

## Dirty State

**Prevents re-triggering until full release**

### What triggers dirty?

**Modifier-only (Option):**
- Add extra modifier within 0.3s → dirty
- Press any key within 0.3s → dirty
- Click mouse within 0.3s → dirty

**Regular (Cmd+A):**
- Press different key within 1s → dirty
- Change modifiers within 1s → dirty

### Dirty behavior

```
User: Hold Option (0.1s) → Add Shift → Release Shift → Press Option again
      ↓
  START → DISCARD (dirty=true) → (ignored) → (ignored)
  
  User must release EVERYTHING (∅) to clear dirty
  
  → Release all keys → Now Option works again
```

### State Flow

**CLEAN** → [trigger dirty condition] → **DIRTY** → [full release (all keys)] → **CLEAN**

- **CLEAN**: Accepts hotkey input
- **DIRTY**: Ignores all input until full release (all keys released)

---

## Decision Tree

**Processing order:**

1. **Is ESC pressed?**
   - YES → CANCEL (exit)

2. **Are we dirty?**
   - YES → Ignore input (unless full release)

3. **Does chord match hotkey exactly?**
   - NO → Check if recording active
     - Recording active → Handle based on elapsed time
     - Not recording → Ignore input
   - YES → Continue to step 4

4. **Is recording active?**
   - NO → START recording
   - YES → Check hotkey type and elapsed time

5. **If recording active:**
   - **Modifier-only?**
     - YES → Check elapsed < max(0.3s, minimumKeyTime)
       - YES → DISCARD or (ignore if ≥0.3s)
       - NO → (ignore)
   - **Regular hotkey?**
     - Check elapsed < 1s
       - YES → Check elapsed < minimumKeyTime
         - YES → DISCARD
         - NO → STOP
       - NO → (ignore)

6. **Final action:**
   - START or STOP (depending on current state)

---

## State Machine

**States:**

- **IDLE**
  - Transition: chord matches hotkey → PRESS & HOLD

- **PRESS & HOLD** (recording)
  - On release (normal):
    - Check elapsed time
    - If < 0.3s (modifier-only) or < minimumKeyTime (regular) → DISCARD
    - If ≥ threshold → Check last tap timing
      - If Δt < 0.3s → LOCK
      - Otherwise → STOP → IDLE
  - On other input:
    - Check elapsed time
    - If < 0.3s → DISCARD → IDLE
    - If ≥ 0.3s → (ignore, keep recording)

- **LOCK** (hands-free recording)
  - Transition: Tap hotkey again OR press ESC → STOP → IDLE

---

## Examples with Full Explanations

### Example 1: Quick Option tap for special character

```
Goal: Type "å" (Option+A)

Timeline:
  t=0.0s  Press Option          → START recording
  t=0.15s Press A               → DISCARD (< 0.3s)
                                  Option+A passes to macOS
  
macOS sees: Option+A
Result: Special character dialog appears ✅
utt: Silent discard, no transcription
```

**Why this works:**
- Recording starts immediately (responsive)
- But discarded if < 0.3s (safety)
- Keys pass through (Option+A reaches macOS)

---

### Example 2: Intentional voice recording with Option

```
Goal: Record a voice note

Timeline:
  t=0.0s  Press Option          → START recording
  t=0.5s  Still holding...      (recording audio)
  t=2.0s  Release Option        → STOP, TRANSCRIBE
  
Result: Audio transcribed and pasted ✅
```

---

### Example 3: Option-click to duplicate

```
Goal: Duplicate file in Finder

Timeline:
  t=0.0s  Press Option          → START recording
  t=0.2s  Click file            → DISCARD (< 0.3s)
                                  Click passes through
  
Finder sees: Option+Click
Result: File duplicated ✅
utt: Silent discard
```

---

### Example 4: Recording while typing

```
Goal: Dictate code comments while typing

Timeline:
  t=0.0s  Press Option          → START recording
  t=0.5s  Still talking...      (recording)
  t=2.0s  Press Cmd+Tab         → IGNORED (> 0.3s)
                                  Cmd+Tab passes through
  t=3.0s  Type some code        → IGNORED
  t=5.0s  Release Option        → STOP, TRANSCRIBE
  
Result: Audio transcribed ✅
        Cmd+Tab worked ✅
        Typing worked ✅
```

**Why:** After 0.3s, utt assumes you're intentionally recording and ignores other input (except ESC).

---

### Example 5: Accidental recording cancellation

```
Goal: Cancel accidental recording

Timeline:
  t=0.0s  Press Option          → START recording
  t=1.0s  "Oh no, accident!"
  t=1.5s  Press ESC             → CANCEL (with sound)
  
Result: Recording cancelled ✅
        Cancel sound plays
```

---

## Summary Table

**Modifier-only (Option):**

- **Time < 0.3s:**
  - Release → Discard
  - Click → Discard
  - Press key → Discard
  - Add modifier → Discard

- **Time ≥ 0.3s:**
  - Release → Transcribe
  - Click → Ignore (keep recording)
  - Press key → Ignore (keep recording)
  - Add modifier → Ignore (keep recording)
  - ESC → Cancel

**Regular (Cmd+A):**

- **Time < minimumKeyTime:**
  - Release → Discard

- **Time: minimumKeyTime - 1s:**
  - Other key → Stop
  - Add modifier → Stop

- **Time > 1s:**
  - Other key → Ignore (keep recording)
  - Add modifier → Ignore (keep recording)

- **Any time:**
  - Release → Transcribe (if long enough)
  - ESC → Cancel

---

## Implementation Files

- **Core Logic**: `UttCore/Sources/UttCore/Logic/HotKeyProcessor.swift`
- **State Transitions**: `UttCore/Sources/UttCore/Logic/HotKeyProcessor+Transitions.swift`
- **Recording Decision**: `UttCore/Sources/UttCore/Logic/RecordingDecision.swift`
- **Feature Integration**: `Utt/Features/Transcription/TranscriptionFeature.swift`
- **Tests**: `UttCore/Tests/UttCoreTests/HotKeyProcessorTests.swift` (not ported yet)

---

## Where this doc drifts from the code

This document was inherited from the reference implementation along with the state
machine, and it describes the *intended* behaviour rather than the shipped one. Where
the two disagree, **the code is the specification** — `HotKeyProcessor` was ported
verbatim. Known divergences, all verified against the port:

1. **A short release does not discard inside the processor.** The doc says a modifier-only
   release under 0.3s produces DISCARD. `HotKeyProcessor` emits `.stopRecording` on *every*
   release of an active press-and-hold, whatever the elapsed time. The discard is enforced
   one layer down, by `RecordingDecisionEngine.decide`, which returns
   `.discardShortRecording` for modifier-only recordings shorter than
   `max(minimumKeyTime, 0.3s)`. Net user-visible behaviour matches the doc; the *output enum
   value* does not, which matters to anything switching on it (sounds, key interception).

2. **Regular hotkeys never discard on duration at all.** The doc's decision matrix says a
   Cmd+A recording under `minimumKeyTime` is discarded. Nothing implements that.
   `RecordingDecisionEngine.decide` ends in `durationIsLongEnough || includesPrintableKey`,
   so any hotkey with a key component always returns `.proceedToTranscription`. A 10ms Cmd+A
   tap is transcribed. `minimumKeyTime` only affects key+modifier hotkeys via the
   *interruption* path (a different key arriving mid-recording yields `.discard` instead of
   `.stopRecording`), never via release.

3. **Mouse clicks never touch regular hotkeys.** The doc lists "Click → DISCARD (silent)"
   under regular hotkeys before 0.2s. `processMouseClick()` returns nil immediately unless
   `hotkey.key == nil`, so clicks are only ever relevant to modifier-only hotkeys.

4. **The double-tap window is release-to-release, not release-to-press.** The doc's rule
   ("2nd tap must be within 0.3s of 1st release") reads as press-timed. The code compares
   the two *release* timestamps: `lastTapAt` is written when a press-and-hold stops, and the
   lock engages only if the next release lands within 0.3s of it. A second tap that starts
   inside the window but is held past it does not lock.

5. **Double-tap-only mode is undocumented.** `useDoubleTapOnly` (with a key+modifier hotkey
   and `doubleTapLockEnabled`) suppresses press-and-hold entirely: the first matching press
   emits nothing and only records a timestamp, the following full release emits
   `.startRecording` and jumps straight to `.doubleTapLock`, and the lock then exits on a
   full release rather than on the next press. The doc's decision tree ("Not recording →
   Ignore input") does not account for this path.

6. **ESC only cancels while recording — and any stray key dirties the processor.** ESC in
   `.idle` returns nil, not `.cancel`, so it is not intercepted. It does, however, count as
   unrelated input for a modifier-only hotkey, which sets the dirty flag; the hotkey stays
   inert until the keyboard is fully released (`key == nil, modifiers == []`). Same for any
   other key pressed while idle.

7. **Output names.** The doc's "Output Types" section lists `.discard`, `.stop`, `.cancel`.
   The enum is `HotKeyProcessor.Output` with cases `.startRecording`, `.stopRecording`,
   `.cancel`, `.discard`.

---

**Document Version:** 2.1  
**Last Updated:** 2026-08-11
