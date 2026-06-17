# The Codetta Language

Codetta is a small declarative language for writing music as code. You define
reusable **chords** and **phrases**, arrange them into **sections** of parallel
**tracks**, and lay those sections out in a **song**. The compiler lowers a
score to a flat list of timed note events, which the toolchain renders as
`@tonejs/midi`-style JSON (for browser playback) or a Standard MIDI File.

This document is a complete reference for the language as implemented. It is
meant to be read end-to-end by a person or a model that needs to author or
reason about `.coda` files.

---

## Table of contents

1. [Program structure](#program-structure)
2. [Comments](#comments)
3. [Settings: `tempo` and `time_signature`](#settings)
4. [Notes and pitches](#notes-and-pitches)
5. [Durations](#durations)
6. [Rests](#rests)
7. [Chords](#chords)
8. [Phrases](#phrases)
9. [Positioning (`@bar.beat`)](#positioning)
10. [Dynamics](#dynamics)
11. [Sections and tracks](#sections-and-tracks)
12. [Transforms](#transforms)
13. [Repetition (`* N`)](#repetition)
14. [Song](#song)
15. [Names and resolution](#names-and-resolution)
16. [Diagnostics](#diagnostics)
17. [Timing model](#timing-model)
18. [Grammar](#grammar)
19. [Worked example](#worked-example)
20. [Cheat sheet](#cheat-sheet)

---

## Program structure

A program is a flat list of top-level declarations:

- `tempo` — a global setting (at most one is meaningful)
- `time_signature` — a global setting (at most one is meaningful)
- `chord` — a named chord definition
- `phrase` — a named phrase definition
- `section` — a named section definition
- `song` — the arrangement; **required**

Declarations may appear in any order — all names are collected before
references are resolved, so forward references work. By convention you write
settings first, then chords, phrases, sections, and the `song` last:

```coda
tempo 120
time_signature 4/4

chord Cmaj = [C4 E4 G4]

phrase melody =
  C4.quarter E4.quarter G4.half

section verse =
  track lead: melody

song =
  verse
```

Whitespace (spaces, tabs, newlines) is insignificant except as a token
separator; indentation is purely stylistic.

---

## Comments

A comment starts with `--` and runs to the end of the line.

```coda
tempo 120        -- beats per minute
-- this whole line is a comment
```

---

## Settings

### `tempo`

```coda
tempo <bpm>
```

Sets the playback speed in beats per minute, where a beat is a quarter note.
`<bpm>` is a positive integer. **Default: 120** if omitted (the compiler emits a
warning).

### `time_signature`

```coda
time_signature <numerator>/<denominator>
```

Sets the meter, e.g. `4/4` or `3/4`. Both parts are positive integers. The meter
determines the length of a bar, which is the basis for durations and positions
(see [Timing model](#timing-model)). **Default: 4/4** if omitted (warning).

---

## Notes and pitches

A note literal is a pitch letter, an optional accidental, and an octave number:

```
<A-G>[#|b]<octave>
```

- **Pitch letter**: `A` `B` `C` `D` `E` `F` `G` (uppercase).
- **Accidental** (optional): `#` raises a semitone, `b` lowers a semitone.
- **Octave**: an integer. `C4` is middle C (MIDI note 60).

Examples: `C4`, `F#3`, `Bb2`, `G5`.

The MIDI number is computed as `(octave + 1) * 12 + semitone + accidental`,
where the semitone offsets are `C=0, D=2, E=4, F=5, G=7, A=9, B=11`. The result
is clamped to the valid MIDI range `0–127`.

A bare note on its own is only a pitch; to sound it you give it a
[duration](#durations): `C4.quarter`.

> **Note on naming:** because a letter `A`–`G` followed only by digits lexes as
> a note literal, you cannot use such a string (e.g. `C4`) as a chord/phrase/
> section name. Ordinary names like `Cmaj`, `bass`, or `melody` are fine.

---

## Durations

A duration is written as a dot, a length keyword, and an optional `.dot` to dot it:

```
.<whole|half|quarter|eighth|sixteenth>[.dot]
```

A duration is a **fraction of a full bar**, not a fixed note value:

| Keyword      | Fraction of a bar |
| ------------ | ----------------- |
| `whole`      | 1 (a full bar)    |
| `half`       | 1/2               |
| `quarter`    | 1/4               |
| `eighth`     | 1/8               |
| `sixteenth`  | 1/16              |

In **4/4** these line up with conventional note values (a `quarter` is a quarter
note). In other meters they remain bar fractions — e.g. in **3/4**, `whole`
spans the whole three-beat bar.

Appending `.dot` lengthens a duration by half (a dotted quarter = a quarter plus
an eighth):

```coda
C4.quarter        -- a quarter of a bar
E4.quarter.dot    -- 1.5× that
rest.half
```

See [Timing model](#timing-model) for exact tick values.

---

## Rests

A rest advances time without sounding anything. It takes the same durations as
notes:

```coda
rest.quarter
C4.quarter rest.quarter C4.half
```

---

## Chords

Define a chord as a named set of notes:

```coda
chord <Name> = [<Note> <Note> ...]
```

```coda
chord Cmaj = [C4 E4 G4]
chord Dmin = [F4 A3 C4 D4]
```

Reference a chord by name plus a duration; all its notes sound simultaneously
for that duration:

```coda
Cmaj.whole        -- C4, E4, G4 together for a whole note
```

Chord references appear inside phrase bodies and directly inside tracks.

---

## Phrases

A phrase is a reusable line of music — a sequence of elements laid out in time:

```coda
phrase <Name> =
  <element> <element> ...
```

A phrase element is one of:

| Element        | Example          | Meaning                                  |
| -------------- | ---------------- | ---------------------------------------- |
| note           | `C4.quarter`     | a single pitch for a duration            |
| rest           | `rest.quarter`   | silence for a duration                   |
| chord ref      | `Cmaj.half`      | a named chord for a duration             |
| positioned     | `@1.1 C3.whole`  | an element pinned to an absolute time    |
| dynamic        | `dynamic @0 p`   | a loudness directive (see below)         |

Plain elements (note, rest, chord) are **juxtaposed in time**: an internal
cursor starts at 0 and advances by each element's duration. So:

```coda
phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter   -- four beats, in sequence
  D4.half C4.half
```

`positioned` and `dynamic` elements are special — see the next two sections.
Phrases are placed onto tracks inside a [section](#sections-and-tracks), where
they may be [transformed](#transforms) and [repeated](#repetition).

Inside a phrase body, a bare name followed by a duration is always a **chord
reference** (e.g. `Cmaj.half`).

---

## Positioning

By default phrase elements follow one another. A position pins the **next**
element to an absolute time within the phrase, independent of (and without
moving) the running cursor — this is how you write polyphony.

```
@<bar>.<beat> <element>
```

`<beat>` is optional and defaults to 0 (`@2` means `@2.0`).

**Positions are 0-based and relative to the start of the phrase.** `@0` (or
`@0.0`) is the very first beat of the phrase; `@1.0` is the start of the second
bar; `@1.1` is the second beat of the second bar. Here the `bar` index multiplies
the bar length and `beat` multiplies the beat length (see [Timing model](#timing-model)).

```coda
phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter
  @1.1 C3.whole        -- a sustained C3 placed under bar 2, beat 2
```

The positioned element does not advance the cursor, so the sequential line and
the positioned voice overlap.

---

## Dynamics

Dynamics set or shape loudness. They are directives, not notes: they establish
velocity breakpoints that every note in the phrase is then resolved against.

> **Scope:** dynamics only have effect **inside a phrase**. Notes and chords
> placed directly on a track (not via a phrase) always use the default velocity.

Two forms, both anchored at a [position](#positioning):

### Level

```coda
dynamic @<pos> <level>
```

Sets the velocity from that position onward. Levels and their MIDI velocities:

| Level | `ppp` | `pp` | `p` | `mp` | `mf` | `f` | `ff` | `fff` |
| ----- | ----- | ---- | --- | ---- | ---- | --- | ---- | ----- |
| Vel.  | 16    | 32   | 48  | 64   | 80   | 96  | 112  | 127   |

The default velocity, used before any dynamic takes effect, is **80 (`mf`)**.

### Shape (crescendo / diminuendo)

```coda
dynamic @<pos> crescendo to <level> over <n> bar
dynamic @<pos> diminuendo to <level> over <n> bars
```

Glides from the currently active level toward `<level>` across `<n>` bars
(`bar` and `bars` are interchangeable). The velocity of each note is linearly
interpolated between the start level and the target based on where the note
falls in the ramp; notes at or past the end of the ramp get the target velocity.

```coda
phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter
  dynamic @0 p                          -- start soft
  dynamic @0.3 crescendo to f over 1 bar   -- swell to forte over one bar
```

Dynamics are assumed to be written in chronological order within a phrase; a
shape ramps from whatever level was active immediately before it (or the default
if none).

---

## Sections and tracks

A section groups **parallel** tracks — voices that play at the same time:

```coda
section <Name> =
  track <name>: <content>
  track <name>: <content>
```

```coda
section verse =
  track melody:  melody
  track counter: melody transpose +2 reverse
  track bass:    bassline
```

Each `track` is one named voice. Its **content** is a phrase reference, a chord
reference, a note, a rest, or a sequence of these, with optional
[transforms](#transforms) and [repetition](#repetition):

```coda
track chords: Cmaj.half Fmaj.half Gmaj.half Cmaj.half   -- a sequence of chords
track bass:   bassline transpose -5                     -- a transformed phrase
track lead:   melody                                    -- a phrase reference
```

A track's items are juxtaposed in time just like phrase elements. The length of
a section is the length of its **longest** track; all tracks start together at
the section's start.

Track names are the voices shown in the player and written to MIDI; the same
name reused across sections refers to the same voice.

> Tracks cannot contain `positioned` or `dynamic` elements directly — those live
> only inside phrase bodies. To get polyphony or dynamics in a track, reference a
> phrase that uses them.

---

## Transforms

Transforms modify a phrase reference, chord, note, or sequence on a track. They
are written after the target and may be chained (applied left to right):

```coda
melody transpose +5 augment x2
```

| Transform            | Effect                                                              |
| -------------------- | ------------------------------------------------------------------- |
| `transpose <+/-n>`   | shifts every pitch by `n` semitones (`+12` = up an octave). The sign is optional; clamped to MIDI `0–127`. |
| `reverse`            | reverses the target in time, so it plays end to start.              |
| `augment x<n>`       | multiplies every duration (and the total length) by `n` — slower.   |
| `diminish x<n>`      | divides every duration by `n` (integer division) — faster.          |

```coda
track counter: melody transpose +2 reverse
track slow:    melody augment x2
track bass:    bassline transpose -5
```

---

## Repetition

`* N` repeats its target `N` times, back to back. It applies to song items,
track items, and sequence items:

```coda
verse * 2                 -- in a song: play the verse twice
bassline * 4              -- on a track: repeat the phrase four times
```

`N` is a positive integer.

---

## Song

The `song` block arranges sections into the finished piece. It is **required** —
without it there is nothing to play.

```coda
song =
  <section> <section> ...
```

Section names are listed in play order; each is placed sequentially after the
previous one (the cursor advances by the placed section's length). Repeat a
section with `* N`:

```coda
song =
  intro
  verse * 2
  chorus
  verse
  chorus * 2
```

---

## Names and resolution

- **Chords**, **phrases**, and **sections** live in three separate namespaces
  keyed by name.
- References are resolved after the whole file is read, so order does not matter
  (a `song` may appear before the sections it names).
- A name is an identifier: a letter or `_` followed by letters, digits, `_`, or
  `#`. It must not match a note literal (a single `A`–`G` followed only by
  digits), since that lexes as a note.
- In a **track**, a bare name (no duration) is a **phrase** reference; a name
  with a duration (`Name.duration`) is a **chord** reference.
- In a **phrase body**, a bare name with a duration is a **chord** reference.

---

## Diagnostics

The compiler reports problems as it checks a score:

**Errors** (block compilation):

- a reference to an undefined `chord`, `phrase`, or `section`;
- no `song` block;
- syntax errors (recovered from where possible so multiple are reported).

**Warnings** (compile still succeeds):

- no `tempo` set (defaults to 120 bpm);
- no `time_signature` set (defaults to 4/4);
- a `chord`, `phrase`, or `section` that is defined but never referenced.

---

## Timing model

All timing is in **ticks**. There are **480 ticks per quarter note** (`ppq`).

Derived quantities, for a meter `num/den`:

- **bar length** = `ppq * num * 4 / den` ticks
- **beat length** = `ppq * 4 / den` ticks (a beat is the meter's denominator unit)

A duration of fraction `f` of a bar is `bar_length * f` ticks (then `× 1.5` if
dotted). In **4/4** (`bar_length = 1920`):

| Duration    | Ticks (4/4) |
| ----------- | ----------- |
| `whole`     | 1920        |
| `half`      | 960         |
| `quarter`   | 480         |
| `eighth`    | 240         |
| `sixteenth` | 120         |
| `quarter.dot` | 720       |

A position `@bar.beat` resolves to `bar * bar_length + beat * beat_length` ticks,
relative to the phrase start (0-based).

Notes carry absolute `ticks` (start) and `durationTicks`. Wall-clock time is a
rendering concern: `seconds = ticks / ppq * (60 / tempo)`. Velocity is `0–127`
(normalized to `0.0–1.0` in the JSON backend).

---

## Grammar

An EBNF sketch (`{ }` = zero or more, `[ ]` = optional, `|` = alternative):

```ebnf
program        = { top_level } ;
top_level      = tempo | time_signature | chord_def | phrase_def
               | section_def | song_def ;

tempo          = "tempo" int ;
time_signature = "time_signature" int "/" int ;

chord_def      = "chord" name "=" "[" { note } "]" ;
phrase_def     = "phrase" name "=" { phrase_element } ;
section_def    = "section" name "=" { track } ;
song_def       = "song" "=" { song_item } ;

track          = "track" name ":" { track_item } ;
track_item     = ( name | note | rest ) [ "." duration_tail ]
                 { transform } [ "*" int ] ;
song_item      = name [ "*" int ] ;

phrase_element = note_elem | rest_elem | chord_ref | positioned | dynamic ;
note_elem      = note duration ;
rest_elem      = "rest" duration ;
chord_ref      = name duration ;
positioned     = "@" position phrase_element ;
dynamic        = "dynamic" "@" position ( level | shape ) ;
shape          = ( "crescendo" | "diminuendo" ) "to" level
                 "over" int ( "bar" | "bars" ) ;

duration       = "." duration_kind [ "." "dot" ] ;
duration_kind  = "whole" | "half" | "quarter" | "eighth" | "sixteenth" ;
position       = int [ "." int ] ;
transform      = "transpose" [ "+" | "-" ] int
               | "reverse"
               | "augment" multiplier
               | "diminish" multiplier ;
multiplier     = "x" int ;
level          = "ppp" | "pp" | "p" | "mp" | "mf" | "f" | "ff" | "fff" ;

note           = ( "A".."G" ) [ "#" | "b" ] int ;
name           = letter { letter | digit | "_" | "#" } ;   (* not a note literal *)
comment        = "--" { any-char-except-newline } ;
```

---

## Worked example

```coda
tempo 120
time_signature 4/4

chord Cmaj = [C4 E4 G4]
chord Fmaj = [F4 A4 C5]
chord Gmaj = [G4 B4 D5]

phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter   -- a four-beat line...
  D4.half C4.half
  @1.1 C3.whole                                    -- ...with a sustained note under bar 2

  dynamic @0 p                                     -- start soft
  dynamic @0.3 crescendo to f over 1 bar           -- swell to forte

phrase bassline =
  C3.whole F3.whole G3.whole C3.whole

section intro =
  track melody: melody
  track bass:   bassline

section verse =
  track melody:  melody
  track counter: melody transpose +2 reverse       -- a transposed, reversed echo
  track bass:    bassline

section chorus =
  track melody: melody transpose +5 augment x2      -- higher and twice as slow
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

## Cheat sheet

```coda
tempo 120                         -- bpm
time_signature 4/4                -- meter

chord Name = [C4 E4 G4]           -- named simultaneous notes

phrase Name =                     -- a line in time
  C4.quarter  rest.eighth  Cmaj.half
  @1.0 G3.whole                   -- polyphony: pin an element (0-based @bar.beat)
  dynamic @0 mp                   -- loudness (phrases only)
  dynamic @0 crescendo to f over 2 bars

section Name =                    -- parallel voices
  track lead: Name                -- a phrase reference
  track bass: Name transpose -12  -- transforms: transpose ± / reverse / augment xN / diminish xN
  track pad:  Cmaj.whole * 4      -- chords, sequences, repeat with * N

song =                            -- required arrangement
  Name  Name * 2  Other
```

Pitches: `C4` (= MIDI 60), accidentals `#`/`b`. Durations are bar fractions:
`whole half quarter eighth sixteenth`, dot with `.dot`. Dynamics: `ppp pp p mp
mf f ff fff` (default `mf`). Comments start with `--`.
