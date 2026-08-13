#!/usr/bin/env python3
"""Regenerate docs/dot-matrix-preview.html from DotMatrix.patterns.

Single source of truth stays UttMark.swift: the preview only exists so shapes
can be checked without building and running the app. Run `just dot-matrix-preview`.

Usage:
    python3 tools/dot-matrix-preview.py
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Utt" / "Design" / "DotMatrix.swift"
OUT = ROOT / "docs" / "dot-matrix-preview.html"

PATTERN_RE = re.compile(r"^\s*\[(\d+(?:\s*,\s*\d+)*)\],?\s*(?://\s*(.*))?$")


def extract_patterns() -> list[dict]:
    patterns = []
    inside = False
    for line in SRC.read_text().splitlines():
        if "static let patterns" in line:
            inside = True
            continue
        if not inside:
            continue
        if line.strip() == "]":
            break
        m = PATTERN_RE.match(line)
        if not m:
            continue
        patterns.append(
            {
                "cells": [int(c) for c in m.group(1).split(",")],
                "name": (m.group(2) or "").strip(),
            }
        )
    return patterns


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>utt — dot-matrix preview</title>
<style>
  :root {
    --bg: #0d0d0f;
    --panel: #17171a;
    --line: #26262b;
    --text: #e8e8ea;
    --dim: #3a3a40;
    --accent: #4fc3f7;
    --recording: #ff5252;
    --dot: 18px;
    --fade: 0.3s;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 32px;
    background: var(--bg);
    color: var(--text);
    font: 13px/1.5 -apple-system, "SF Mono", Menlo, monospace;
  }
  header {
    display: flex;
    align-items: baseline;
    gap: 16px;
    flex-wrap: wrap;
    margin-bottom: 12px;
  }
  h1 { font-size: 16px; margin: 0; }
  h1 span { color: var(--accent); }
  header .meta { color: #8a8a90; }
  header .meta b { color: var(--text); }
  .controls {
    display: flex;
    gap: 20px;
    align-items: center;
    flex-wrap: wrap;
    padding: 10px 14px;
    background: var(--panel);
    border: 1px solid var(--line);
    border-radius: 8px;
    margin-bottom: 20px;
  }
  .controls label { display: flex; align-items: center; gap: 8px; color: #8a8a90; }
  .controls input[type="range"] { width: 120px; }
  .controls .play {
    background: var(--accent);
    color: #0d0d0f;
    border: 0;
    border-radius: 6px;
    padding: 5px 14px;
    font: inherit;
    font-weight: 600;
    cursor: pointer;
  }
  .controls .play.recording { background: var(--recording); }
  .stage {
    background: var(--panel);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 24px;
    margin-bottom: 20px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 14px;
  }
  .stage .readout { color: #8a8a90; font-size: 12px; }
  .stage .readout b { color: var(--text); }
  .board {
    display: grid;
    grid-template-columns: repeat(6, var(--cell));
    grid-auto-rows: var(--cell);
    gap: 2px;
    width: fit-content;
  }
  .stage .board { --cell: var(--dot); }
  .dot { border-radius: 50%; }
  /* Stage dots move like the app: lit grow + brighten, dim shrink + fade out. */
  .stage .dot {
    transform: scale(var(--s, 0.62));
    opacity: var(--o, 0.5);
    background: var(--c, var(--dim));
    transition: transform var(--fade) ease-in-out, opacity var(--fade) ease-in-out,
                background-color var(--fade) ease-in-out;
  }
  .stage .dot.lit { --s: 1; --o: 1; --c: var(--accent); }
  .stage .dot.recording { --c: var(--recording); }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
    gap: 14px;
  }
  .grid .board { --cell: 10px; }
  .grid .dot.lit { background: var(--accent); }
  .grid .dot.dim { background: var(--dim); opacity: 0.55; }
  .grid .dot.recording { background: var(--recording); }
  .pattern {
    background: var(--panel);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 12px;
    cursor: pointer;
    transition: border-color 0.15s;
  }
  .pattern:hover { border-color: #3c3c44; }
  .pattern.current { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent) inset; }
  .pattern .name {
    color: #8a8a90;
    font-size: 11px;
    margin-bottom: 10px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .pattern .name b { color: var(--text); font-weight: 600; }
</style>
</head>
<body>
<header>
  <h1>utt<span>.</span> dot matrix — <span id="count"></span></h1>
  <span class="meta">generated from <b>Utt/Design/DotMatrix.swift</b> — add a shape there, then <b>just dot-matrix-preview</b></span>
</header>

<div class="controls">
  <button class="play" id="play">⏸ pause</button>
  <label>cycle speed <input type="range" id="speed" min="50" max="1500" value="400"></label>
  <label>stage dot size <input type="range" id="dot-size" min="8" max="36" value="18"></label>
  <label>recording <input type="checkbox" id="recording"></label>
</div>

<div class="stage">
  <div class="board" id="stage-board"></div>
  <div class="readout" id="readout"></div>
</div>

<div class="grid" id="grid"></div>

<script>
const patterns = __PATTERNS__;

const grid = document.getElementById('grid');
for (let i = 0; i < patterns.length; i++) {
  const p = patterns[i];
  const card = document.createElement('div');
  card.className = 'pattern';
  card.dataset.index = i;

  const name = document.createElement('div');
  name.className = 'name';
  name.innerHTML = `<b>${i}</b> ${escapeHtml(p.name || '—')}`;

  const board = document.createElement('div');
  board.className = 'board';
  for (let cell = 0; cell < 36; cell++) {
    const dot = document.createElement('span');
    dot.className = 'dot ' + (p.cells.includes(cell) ? 'lit' : 'dim');
    board.appendChild(dot);
  }
  card.append(name, board);
  grid.appendChild(card);
}

const stage = document.getElementById('stage-board');
const stageDots = [];
for (let cell = 0; cell < 36; cell++) {
  const dot = document.createElement('span');
  dot.className = 'dot dim';
  stage.appendChild(dot);
  stageDots.push(dot);
}

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

const dotSize = document.getElementById('dot-size');
dotSize.addEventListener('input', () =>
  document.documentElement.style.setProperty('--dot', dotSize.value + 'px'));

const speed = document.getElementById('speed');
function applyFade() {
  document.documentElement.style.setProperty('--fade', Math.min(400, speed.value * 0.5) + 'ms');
}
speed.addEventListener('input', () => { applyFade(); if (playing) restart(); });
applyFade();

const recordingToggle = document.getElementById('recording');
recordingToggle.addEventListener('change', () => {
  const on = recordingToggle.checked;
  document.querySelectorAll('.dot.lit').forEach(d => d.classList.toggle('recording', on));
  document.getElementById('play').classList.toggle('recording', on);
});

const play = document.getElementById('play');
const readout = document.getElementById('readout');
const count = document.getElementById('count');
count.textContent = patterns.length + ' patterns';

let index = 0;
let timer = null;
let playing = true;

function render(i) {
  const lit = new Set(patterns[i].cells);
  for (let cell = 0; cell < 36; cell++) {
    stageDots[cell].classList.toggle('lit', lit.has(cell));
    stageDots[cell].classList.toggle('dim', !lit.has(cell));
    stageDots[cell].classList.toggle('recording', recordingToggle.checked && lit.has(cell));
  }
  readout.innerHTML = `<b>${i}</b> / ${patterns.length - 1} — ${escapeHtml(patterns[i].name || '—')} · ${patterns[i].cells.length} lit`;
  document.querySelectorAll('.pattern').forEach(c => c.classList.remove('current'));
  document.querySelector(`.pattern[data-index="${i}"]`).classList.add('current');
}

function schedule() {
  timer = setTimeout(() => {
    index = (index + 1) % patterns.length;
    render(index);
    schedule();
  }, speed.value);
}

function restart() {
  if (timer) clearTimeout(timer);
  if (playing) schedule();
}

play.addEventListener('click', () => {
  playing = !playing;
  play.textContent = playing ? '⏸ pause' : '▶ animate';
  if (playing) schedule(); else clearTimeout(timer);
});

grid.addEventListener('click', (e) => {
  const card = e.target.closest('.pattern');
  if (!card) return;
  playing = false;
  play.textContent = '▶ animate';
  clearTimeout(timer);
  index = +card.dataset.index;
  render(index);
});

render(0);
schedule();
</script>
</body>
</html>
"""


def main() -> None:
    patterns = extract_patterns()
    if not patterns:
        raise SystemExit(f"error: no patterns parsed from {SRC}")
    html = TEMPLATE.replace(
        "__PATTERNS__", json.dumps(patterns, separators=(",", ":"))
    )
    OUT.write_text(html)
    print(f"wrote {OUT} ({len(patterns)} patterns)")


if __name__ == "__main__":
    main()