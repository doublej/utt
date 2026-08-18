import { closeMainWindow, showHUD } from "@raycast/api";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

/**
 * Start or stop a recording through utt's URL scheme.
 *
 * `-g` is load-bearing: utt pastes into whatever is frontmost when the recording
 * stops, and a plain `open` would put utt itself there. Raycast's own window goes
 * first for the same reason.
 */
export default async function Command() {
  await closeMainWindow();
  try {
    await run("/usr/bin/open", ["-g", "utt://toggle"]);
  } catch {
    // The only realistic failure is utt not being installed — nothing has
    // registered the scheme, so `open` exits non-zero.
    await showHUD("utt is not installed");
  }
}
