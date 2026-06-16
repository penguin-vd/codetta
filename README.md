# Codetta

Codetta is a small compiled language for writing music as code. You describe
melodies, chords, dynamics, and song structure in a `.coda` file, and Codetta
parses, lowers, and compiles it down to a Standard MIDI File.

## A taste

```coda
tempo 120
time_signature 4/4

chord Cmaj = [C4 E4 G4]

phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter
  D4.half C4.half

  dynamic @0 p
  dynamic @0.3 crescendo to f over 1 bar

section verse =
  track melody: melody
  track chords: Cmaj.whole

song =
  verse * 2
```

See [`examples/song.coda`](examples/song.coda) for a fuller example, including
sections, repetition, and phrase transformations like `transpose` and
`reverse`.

## Building

Codetta targets Zig 0.16. From the project root:

```sh
zig build
```

This produces a `codetta` binary in `zig-out/bin/`. Run the test suite with:

```sh
zig build test
```

## Usage

```
Usage: codetta <command> <input.coda> [options]

Commands:
  midi <input> [-o <output>]   Compile to a Standard MIDI File
  web <input> [-o <output>]    Compile to @tonejs/midi-style JSON
  inspect-ast <input>          Print the parsed syntax tree
  inspect-score <input>        Print the lowered Score IR
  check <input>                Parse and lower without producing output

Options:
  -h, --help                   Show this help message
```

For example, to compile the example song to MIDI:

```sh
zig build run -- midi examples/song.coda -o song.mid
```

## Web app

Codetta compiles to a WebAssembly module that runs the whole pipeline in the
browser, so you can write songs in a live editor and hear them played through
[Tone.js](https://tonejs.github.io/) synths. Every keystroke is compiled to a
`Score` via the `web` backend (exposed through `src/wasm.zig`), drawn as a
piano-roll, and the same module also exports a Standard MIDI File.

The frontend is a Vite + React app in [`app/`](app/) — a syntax-highlighted
editor, a piano-roll with a moving playhead, and a channel strip per track with
a selectable instrument:

```sh
cd app && npm install && npm run dev   # builds the WASM module, then serves
```

`npm run dev` runs `zig build wasm` for you; to build the module on its own (it
lands in `app/public/codetta.wasm`):

```sh
zig build wasm
```

## Project layout

- `src/lexer`, `src/parser`: turn `.coda` source into an AST
- `src/ir`: lowers the AST into a `Score`, the intermediate representation
  shared by all backends
- `src/midi`: compiles a `Score` to a Standard MIDI File
- `src/web`: compiles a `Score` to @tonejs/midi-style JSON for the browser
- `src/diag`: collects all diagnostics at once — recovered syntax errors plus
  lint rules (missing `tempo`/`time_signature`, undefined references, and
  defined-but-unused chords/phrases/sections)
- `src/inspect`: pretty-prints the AST and `Score` for debugging
- `src/cli`, `src/commands.zig`: the subcommand-based CLI
- `src/wasm.zig`: the freestanding WASM entry point used by the web app
- `app/`: the Vite + React frontend (editor, piano-roll, Tone.js playback)

A new backend is a new subcommand plus a function in `commands.zig` that
feeds it a `Score`.
