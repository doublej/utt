// OpenCode compiles a plugin's JSX only outside node_modules, so the npm package ships
// dist/tui.js, already through the Solid transform. The host modules stay imports:
// OpenCode supplies them, and a bundled second solid-js would break reactivity.
import solid from "@opentui/solid/bun-plugin"

const result = await Bun.build({
  entrypoints: ["./tui.ts"],
  outdir: "./dist",
  target: "bun",
  format: "esm",
  plugins: [solid],
  external: ["solid-js", "solid-js/*", "@opentui/*", "@opencode/*"],
})

if (!result.success) {
  for (const log of result.logs) console.error(log)
  process.exit(1)
}
