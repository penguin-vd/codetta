# Codetta — web app

A Vite + React frontend for writing Codetta songs in the browser. It runs the
whole compiler in WebAssembly: every keystroke is compiled to a `Score` by
`codetta.wasm` and rendered as a piano-roll you can play through Tone.js synths.

## Running

```sh
npm install
npm run dev        # builds codetta.wasm (via `zig build wasm`), then serves
```

Open http://localhost:5173. `npm run build` produces a static bundle in `dist/`.

The `predev`/`prebuild` scripts invoke `zig build wasm`, so a Zig 0.16 toolchain
must be on `PATH`. The module lands in `public/codetta.wasm`.

## How it fits together

- `src/wasm.ts` — loads the module and exposes `compileSong` / `compileMidi`
- `src/audio.ts` — the Tone.js engine and instrument presets
- `src/coda-language.ts` — CodeMirror syntax highlighting for `.coda`
- `src/components` — `Editor`, `Transport`, `PianoRoll`, `TrackRail`

Editing the language or backends? Rebuild the module with `npm run wasm`.
