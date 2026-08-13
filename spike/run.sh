#!/usr/bin/env zsh
# Drive the spike: throwaway TextEdit doc -> run signed app -> read results -> clean up.
set -uo pipefail
cd "${0:h}"

TARGET="$PWD/spike-target.txt"
OUT="$PWD/spike-result.jsonl"

rm -f "$OUT" spike-mic.wav
: > "$TARGET"

open -a TextEdit "$TARGET"
sleep 2

SPIKE_OUT="$OUT" open -n --wait-apps --env SPIKE_OUT="$OUT" ./Spike.app &
OPEN_PID=$!

# Poll for completion (the app polls up to 120s for each TCC grant).
for i in {1..200}; do
    grep -q '"check":"done"' "$OUT" 2>/dev/null && break
    grep -q '"check":"abort"' "$OUT" 2>/dev/null && break
    sleep 1
done
sleep 1
kill $OPEN_PID 2>/dev/null
pkill -f 'Spike.app/Contents/MacOS/utt' 2>/dev/null

echo "===== spike-result.jsonl ====="
cat "$OUT" 2>/dev/null
echo "===== TextEdit document contents ====="
cat "$TARGET" 2>/dev/null | od -c | head -5
echo "===== mic wav ====="
ls -la spike-mic.wav 2>/dev/null || echo "(none)"

# clean up the user's screen
pkill -x TextEdit 2>/dev/null
sleep 1
rm -f "$TARGET"
