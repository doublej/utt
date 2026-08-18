/**
 * utt keeps everything it knows in plain JSON under Application Support, and the
 * running app watches those files — so writing `settings.json` here changes the
 * microphone of a live app, no scripting bridge and no relaunch.
 *
 * That is also the whole integration: there is no separate API to drift out of
 * sync with the one the app itself reads.
 */
import { readFile, writeFile, rename } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

/** Overridable so the tests can work on a throwaway directory instead of the
 * real one — a bug in `writePriority` would otherwise cost the user every setting. */
export const SUPPORT_DIR =
  process.env.UTT_SUPPORT_DIR ?? join(homedir(), "Library", "Application Support", "dev.jurrejan.utt");

const SETTINGS_FILE = join(SUPPORT_DIR, "settings.json");
const HISTORY_FILE = join(SUPPORT_DIR, "history.json");
const DEVICES_FILE = join(SUPPORT_DIR, "devices.json");

/** One input, keyed by its CoreAudio UID — the id `microphonePriority` stores. */
export interface AudioDevice {
  id: string;
  name: string;
}

export interface Transcript {
  id: string;
  /** Seconds since 2001-01-01, which is what Swift's `Date` encodes to. */
  timestamp: number;
  text: string;
  duration: number;
  sourceAppName?: string;
  sourceAppBundleID?: string;
}

/** Settings are read as an opaque object so a key this extension knows nothing
 * about survives a write. utt's own decoder ignores keys it does not recognise,
 * but it cannot bring back one that was dropped on the way through here. */
type Settings = Record<string, unknown> & { microphonePriority?: string[] };

async function readJSON<T>(path: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch {
    // Missing means utt has not written it yet — a first launch, or a device
    // list from a version that did not export one. Not an error worth a toast.
    return fallback;
  }
}

export async function readDevices(): Promise<AudioDevice[]> {
  return readJSON<AudioDevice[]>(DEVICES_FILE, []);
}

export async function readHistory(): Promise<Transcript[]> {
  const history = await readJSON<{ history?: Transcript[] }>(HISTORY_FILE, {});
  return history.history ?? [];
}

export async function readPriority(): Promise<string[]> {
  const settings = await readJSON<Settings>(SETTINGS_FILE, {});
  if (Array.isArray(settings.microphonePriority)) return settings.microphonePriority;
  // Files written before the priority list existed still name one microphone.
  const legacy = settings.selectedMicrophoneID;
  return typeof legacy === "string" ? [legacy] : [];
}

/**
 * Read, change the priority list, write back.
 *
 * ponytail: last writer wins — utt could save settings in the same instant and
 * clobber this. Changing a microphone is a deliberate, occasional act, so the
 * window is not worth a lock file. Add one if this ever grows into something
 * that writes on a timer.
 */
export async function writePriority(priority: string[]): Promise<void> {
  const settings = await readJSON<Settings>(SETTINGS_FILE, {});
  settings.microphonePriority = priority;
  // An empty list means "system default", and utt only falls back to the legacy
  // key when `microphonePriority` is absent — but leaving a stale single mic in
  // the file is exactly the kind of thing that resurfaces later. Drop it.
  delete settings.selectedMicrophoneID;

  // Atomic: utt watches this path, and a half-written file would decode to
  // defaults and reset every setting the user has.
  const temporary = `${SETTINGS_FILE}.raycast-${process.pid}`;
  await writeFile(temporary, JSON.stringify(settings), "utf8");
  await rename(temporary, SETTINGS_FILE);
}

/** Swift's reference date is 2001-01-01, JavaScript's is 1970-01-01. */
export function toDate(timestamp: number): Date {
  return new Date((timestamp + 978_307_200) * 1000);
}
