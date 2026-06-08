# Music Language Specification
> A compiled, composition-first language for writing music.

---

## Philosophy

Most music languages are **loop-first** — everything is a repeating pattern. This language is **composition-first**. It thinks in song structure: sections, phrases, development, and form. Loops exist but are opt-in, not the default.

---

## Top-level Structure

A file consists of:
1. Global settings (`tempo`, `time_signature`)
2. Definitions (`chord`, `phrase`)
3. Sections (`section`)
4. A `song` declaration

```
tempo 120
time_signature 4/4

-- definitions...

song =
  intro
  verse * 2
  chorus
```

---

## Comments

```
-- this is a comment
```

---

## Global Settings

```
tempo 120          -- BPM
time_signature 4/4
```

---

## Notes

Notes are written as `pitch + octave + duration`:

```
C4.quarter
E4.half
G4.whole
Bb3.quarter        -- flat
F#5.eighth         -- sharp
```

### Pitches
`C D E F G A B` with optional `#` (sharp) or `b` (flat).

### Octaves
Integer suffix on the pitch: `C4`, `G3`, `A5`.

### Durations
| Name | Symbol |
|---|---|
| `whole` | 1 bar |
| `half` | 1/2 bar |
| `quarter` | 1/4 bar |
| `eighth` | 1/8 bar |
| `sixteenth` | 1/16 bar |

Dotted durations extend by half: `C4.quarter.dot`

---

## Rests

```
rest.quarter
rest.half
rest.whole
```

---

## Chords

Chords are named groups of simultaneous notes:

```
chord Cmaj = [C4 E4 G4]
chord Fmaj = [F4 A4 C5]
chord Gmaj = [G4 B4 D5]
```

Used inside phrases like a regular note, with a duration:

```
Cmaj.half
Fmaj.whole
```

---

## Phrases

A phrase is a reusable musical idea — a sequence of notes, rests, and chords. It can also contain polyphony and dynamics.

```
phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter
  D4.half C4.half
```

### Polyphony via `@` (absolute bar.beat time)

When notes need to overlap with different durations, use `@bar.beat` to place them at an absolute position within the phrase:

```
phrase opening =
  C4.quarter E4.quarter G4.quarter rest.quarter
  @1.1 C3.whole       -- bar 1, beat 1: bass note held under melody
  @1.3 G3.half        -- bar 1, beat 3: inner voice enters
```

`@` positions are relative to the start of the phrase, not the song.

---

## Dynamics

Dynamics are a separate layer inside a phrase, not attached to individual notes:

```
phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter

  dynamic @0 p
  dynamic @0.3 crescendo to f over 1 bar
  dynamic @2.1 ff
```

### Dynamic levels (classical shorthand)
`ppp` `pp` `p` `mp` `mf` `f` `ff` `fff`

### Shaped dynamics
```
dynamic @1.1 crescendo to ff over 2 bars
dynamic @3.1 diminuendo to pp over 1 bar
```

---

## Phrase Transformations

Transformations are applied with a simple `phrase transform args` syntax, left to right:

```
melody transpose +5
melody reverse
melody augment x2       -- double all durations
melody diminish x2      -- halve all durations
melody transpose +5 reverse augment x2   -- chained
```

### Available transformations
| Transformation | Description |
|---|---|
| `transpose +N` / `transpose -N` | Shift pitch by N semitones |
| `reverse` | Reverse the note order |
| `augment xN` | Multiply all durations by N |
| `diminish xN` | Divide all durations by N |
| `humanize N` | Add slight timing/velocity variation (0.0–1.0) |

---

## Repetition

```
melody * 2          -- play twice
melody * 4          -- play four times
```

---

## Sections

A section defines what plays simultaneously across multiple tracks:

```
section verse =
  track melody:  melody * 2
  track bass:    C3.whole * 4
  track chords:  Cmaj.whole Fmaj.whole * 2
```

Each `track` is a named voice. Tracks within a section play in parallel.

---

## Song

The `song` declaration defines the top-level sequence of sections:

```
song =
  intro
  verse * 2
  chorus
  verse
  chorus * 2
```

Sections play sequentially. Repetition uses `* N`.

---

## Full Example

```
tempo 120
time_signature 4/4

chord Cmaj = [C4 E4 G4]
chord Fmaj = [F4 A4 C5]
chord Gmaj = [G4 B4 D5]

phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter
  D4.half C4.half
  @1.1 C3.whole

  dynamic @0 p
  dynamic @0.3 crescendo to f over 1 bar

phrase variation =
  melody transpose +2 reverse

phrase bassline =
  C3.whole F3.whole G3.whole C3.whole

section intro =
  track melody: melody
  track bass:   bassline

section verse =
  track melody:  melody
  track counter: variation
  track bass:    bassline

section chorus =
  track melody: melody transpose +5 augment x2
  track chords: Cmaj.half Fmaj.half Gmaj.half Cmaj.half
  track bass:   bassline transpose -5

song =
  intro
  verse * 2
  chorus
  verse
  chorus * 2
```

---

## Planned / Future

- **Functions** — reusable transformations with parameters
- **Scale / interval library** — derive chords from theory (`C major`, `G mixolydian`)
- **Voice leading** — automatic smooth chord transitions
- **Articulation** — `legato`, `staccato`, `accent` as phrase modifiers
- **Targets** — MIDI file output, WASM/Web Audio for browser playback
