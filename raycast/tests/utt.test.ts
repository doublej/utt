/**
 * `bun test` from `raycast/`. Covers the one thing here that can lose data:
 * a settings write that drops keys this extension does not know about.
 */
import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

let directory: string;

beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), "utt-raycast-"));
  process.env.UTT_SUPPORT_DIR = directory;
});

afterEach(async () => {
  await rm(directory, { recursive: true, force: true });
});

/** Imported per test: `SUPPORT_DIR` is read once at module load. */
async function load() {
  return import(`../src/utt.ts?${directory}`);
}

async function settings() {
  return JSON.parse(await readFile(join(directory, "settings.json"), "utf8"));
}

test("writing the priority leaves every other setting alone", async () => {
  await writeFile(
    join(directory, "settings.json"),
    JSON.stringify({ hotkey: { modifiers: [] }, minimumKeyTime: 0.1, aKeyFromTheFuture: true })
  );
  const { writePriority } = await load();

  await writePriority(["airpods", "yeti"]);

  expect(await settings()).toEqual({
    hotkey: { modifiers: [] },
    minimumKeyTime: 0.1,
    aKeyFromTheFuture: true,
    microphonePriority: ["airpods", "yeti"],
  });
});

test("clearing the list drops the legacy single-microphone key", async () => {
  await writeFile(join(directory, "settings.json"), JSON.stringify({ selectedMicrophoneID: "old" }));
  const { writePriority, readPriority } = await load();

  expect(await readPriority()).toEqual(["old"]);
  await writePriority([]);

  expect(await settings()).toEqual({ microphonePriority: [] });
});

test("a missing settings file is written from scratch", async () => {
  const { writePriority } = await load();
  await writePriority(["builtin"]);
  expect(await settings()).toEqual({ microphonePriority: ["builtin"] });
});

test("timestamps convert from Swift's reference date", async () => {
  const { toDate } = await load();
  expect(toDate(0).toISOString()).toBe("2001-01-01T00:00:00.000Z");
});
