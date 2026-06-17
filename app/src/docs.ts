// The bundled language reference. Each entry is one keyword or concept,
// reachable at #/docs/<slug> and linked to from the editor's hover tooltip.

export type DocKind = "Setting" | "Definition" | "Primitive" | "Transform";

export interface DocEntry {
  slug: string;
  title: string;
  kind: DocKind;
  summary: string;
  syntax: string;
  example: string;
  body: string[];
  // Other words that should resolve to this entry (e.g. a keyword whose hover
  // links here, or plural/variant spellings).
  aliases?: string[];
  see?: string[];
}

export const DOCS: DocEntry[] = [
  {
    slug: "tempo",
    title: "tempo",
    kind: "Setting",
    summary: "Sets the playback speed in beats per minute.",
    syntax: "tempo <bpm>",
    example: "tempo 120",
    body: [
      "A score has a single tempo, written once near the top, applied to the whole song.",
      "If omitted, Codetta defaults to 120 bpm and the editor shows a hint.",
    ],
    see: ["time_signature"],
  },
  {
    slug: "time_signature",
    title: "time_signature",
    kind: "Setting",
    summary: "Sets the meter as beats-per-bar over the beat unit.",
    syntax: "time_signature <numerator>/<denominator>",
    example: "time_signature 4/4",
    body: [
      "Controls how bars and beats are counted, which is what positions like @1.1 refer to.",
      "Defaults to 4/4 when omitted.",
    ],
    see: ["position", "tempo"],
  },
  {
    slug: "chord",
    title: "chord",
    kind: "Definition",
    summary: "Names a stack of notes you can play as a unit.",
    syntax: "chord <Name> = [<Note> <Note> ...]",
    example: "chord Cmaj = [C4 E4 G4]",
    body: [
      "Each note is a pitch letter A–G, an optional accidental (# or b), and an octave number — C4 is middle C (MIDI 60).",
      "Reference a chord by name plus a duration: Cmaj.half. A chord that is never referenced is flagged as unused.",
      "You can also write inline chords directly: [C4 E4 G4].whole — no definition needed.",
    ],
    see: ["note", "phrase", "duration", "arp"],
  },
  {
    slug: "phrase",
    title: "phrase",
    kind: "Definition",
    summary: "A reusable line of music — notes, rests, chords, and dynamics in time.",
    syntax: "phrase <Name> =\n  <element> <element> ...",
    example: "phrase melody =\n  C4.quarter E4.quarter G4.half\n  [C4 E4 G4].2whole arp.bounce x2\n  dynamic @0 p",
    body: [
      "Elements are juxtaposed in time: a note (C4.quarter), a rest (rest.quarter), a chord reference (Cmaj.half), an inline chord ([C4 E4 G4].whole), a positioned element (@1.1 C3.whole), or a dynamic.",
      "Elements can have transforms (transpose, reverse, arp, etc.) and repeats (* N) applied directly.",
      "Phrases are placed onto tracks inside a section, where they can be further transformed and repeated.",
    ],
    see: ["note", "rest", "chord", "position", "dynamic", "section", "arp"],
  },
  {
    slug: "section",
    title: "section",
    kind: "Definition",
    summary: "Groups parallel tracks that play together.",
    syntax: "section <Name> =\n  track <name>: <content>\n  track <name>: <content>",
    example: "section verse =\n  track melody: melody\n  track bass:   bassline transpose -5",
    body: [
      "Each track is one voice. Its content can be a phrase name, chord references, bare notes, or a sequence of them, optionally transformed or repeated.",
      "Sections are arranged into the final piece by the song block.",
    ],
    see: ["track", "phrase", "song", "transpose"],
  },
  {
    slug: "track",
    title: "track",
    kind: "Definition",
    summary: "A single named voice within a section.",
    syntax: "track <name>: <content>",
    example: "track bass: bassline transpose -5 reverse\ntrack keys: [C4 E4 G4].whole arp.bounce x2",
    body: [
      "Track content is a phrase reference, chord refs, inline chords ([C4 E4].whole), notes, or a sequence of them, with optional transforms (transpose, reverse, augment, diminish, arp) and repeats (* N).",
      "The track name becomes the voice shown in the player and MIDI export.",
    ],
    see: ["section", "transpose", "reverse", "repeat", "arp", "chord"],
  },
  {
    slug: "song",
    title: "song",
    kind: "Definition",
    summary: "Arranges sections in order into the finished piece.",
    syntax: "song =\n  <section> <section> ...",
    example: "song =\n  intro\n  verse * 2\n  chorus",
    body: [
      "Lists section names in play order. Repeat a section with * N (verse * 2).",
      "Without a song block there is nothing to play, and the editor reports an error.",
    ],
    see: ["section", "repeat"],
  },
  {
    slug: "note",
    title: "note",
    kind: "Primitive",
    summary: "A single pitch with a duration.",
    syntax: "<Pitch><octave>.<duration>",
    example: "C4.quarter   F#3.eighth   Bb4.half",
    body: [
      "A pitch is a letter A–G with an optional accidental: # (sharp) or b (flat). The trailing number is the octave; C4 is middle C (MIDI 60).",
      "Notes appear inside phrases and directly on tracks.",
    ],
    aliases: ["notes"],
    see: ["duration", "chord", "rest"],
  },
  {
    slug: "duration",
    title: "duration",
    kind: "Primitive",
    summary: "How long a note, rest, or chord lasts.",
    syntax: ".[N]<whole | half | quarter | eighth | sixteenth>[.dot]",
    example: "C4.quarter   rest.half   Cmaj.whole   E4.quarter.dot   C4.2whole",
    body: [
      "A duration attaches with a dot: C4.quarter. The available lengths are whole, half, quarter, eighth, and sixteenth.",
      "Add .dot to dot a duration, extending it by half — a dotted quarter equals a quarter plus an eighth.",
      "Prefix with a number to multiply: .2whole spans two bars, .3half spans one and a half bars.",
    ],
    aliases: ["durations", "whole", "half", "quarter", "eighth", "sixteenth", "dot", "dotted"],
    see: ["note", "rest"],
  },
  {
    slug: "rest",
    title: "rest",
    kind: "Primitive",
    summary: "A silence of a given duration.",
    syntax: "rest.<duration>",
    example: "C4.quarter rest.quarter C4.half",
    body: ["A rest advances time without sounding a note. It takes the same durations as notes."],
    see: ["duration", "note"],
  },
  {
    slug: "dynamic",
    title: "dynamic",
    kind: "Primitive",
    summary: "Sets or shapes loudness across a phrase.",
    syntax: "dynamic @<pos> <level>\ndynamic @<pos> crescendo | diminuendo to <level> over <n> bar(s)",
    example: "dynamic @0 p\ndynamic @0.3 crescendo to f over 1 bar",
    body: [
      "Levels run from ppp (softest) through pp, p, mp, mf, f, ff, to fff (loudest).",
      "A level sets the volume from its position onward. A crescendo or diminuendo glides toward a target level across a number of bars.",
    ],
    aliases: ["dynamics", "crescendo", "diminuendo", "ppp", "pp", "p", "mp", "mf", "f", "ff", "fff", "to", "over"],
    see: ["position", "phrase"],
  },
  {
    slug: "position",
    title: "voice / positioning",
    kind: "Primitive",
    summary: "Resets the cursor to an exact bar and beat.",
    syntax: "@<bar>.<beat>",
    example: "phrase melody =\n  E4.whole E4.quarter\n  @0 C4.quarter C4.whole",
    body: [
      "Resets the cursor to the given bar and beat. Notes that follow are placed sequentially from that point, creating a second voice.",
      "Use it for counterpoint: the first line of notes runs forward, then @0 starts a new voice from the beginning.",
      "Bars and beats are 0-based and follow the current time signature.",
    ],
    aliases: ["voice", "at"],
    see: ["time_signature", "dynamic", "phrase"],
  },
  {
    slug: "repeat",
    title: "repeat",
    kind: "Transform",
    summary: "Repeats a section, track, or element N times.",
    syntax: "<target> * <count>",
    example: "verse * 2   bassline * 4",
    body: ["Multiplies the target in place. Used in songs (verse * 2), on tracks, and within sequences."],
    see: ["song", "section"],
  },
  {
    slug: "transpose",
    title: "transpose",
    kind: "Transform",
    summary: "Shifts pitch up or down by semitones.",
    syntax: "<target> transpose <+|-><n>",
    example: "melody transpose +5   bass transpose -5",
    body: [
      "Moves every pitch in the target by the given number of semitones; +12 is one octave up.",
      "Chain it with other transforms: melody transpose +5 augment x2.",
    ],
    see: ["reverse", "augment", "diminish", "track"],
  },
  {
    slug: "reverse",
    title: "reverse",
    kind: "Transform",
    summary: "Plays the target backwards in time.",
    syntax: "<target> reverse",
    example: "melody reverse",
    body: ["Reverses the order of events so the line plays end to start."],
    see: ["transpose", "track"],
  },
  {
    slug: "augment",
    title: "augment",
    kind: "Transform",
    summary: "Stretches durations by a factor.",
    syntax: "<target> augment x<n>",
    example: "melody augment x2",
    body: ["Multiplies every duration, slowing the line down — augment x2 makes it twice as long."],
    see: ["diminish", "duration"],
  },
  {
    slug: "diminish",
    title: "diminish",
    kind: "Transform",
    summary: "Compresses durations by a factor.",
    syntax: "<target> diminish x<n>",
    example: "melody diminish x2",
    body: ["Divides every duration, speeding the line up — the inverse of augment."],
    see: ["augment", "duration"],
  },
  {
    slug: "arp",
    title: "arp",
    kind: "Transform",
    summary: "Arpeggiates a chord across its duration.",
    syntax: "<target> arp[.mode] [xN]",
    example: "Cmaj.whole arp\nCmaj.whole arp.down\nCmaj.2whole arp.bounce x2",
    body: [
      "Spreads simultaneous notes out in time. Modes: arp (or arp.up) plays low to high; arp.down plays high to low; arp.up_down goes up then down without repeating endpoints; arp.bounce goes up then down with repeated endpoints.",
      "Add xN to cycle the pattern N times within the same duration. Combine with multi-bar durations (e.g. .2whole) for longer arpeggios.",
    ],
    aliases: ["up", "down", "up_down", "bounce"],
    see: ["transpose", "reverse", "track", "chord"],
  },
];

export const DOC_KINDS: DocKind[] = ["Setting", "Definition", "Primitive", "Transform"];

const bySlug = new Map(DOCS.map((d) => [d.slug, d]));

// word/alias -> slug, so a hovered keyword resolves to the entry that documents it.
const byWord = new Map<string, string>();
for (const d of DOCS) {
  byWord.set(d.slug, d.slug);
  for (const a of d.aliases ?? []) byWord.set(a, d.slug);
}

export const docBySlug = (slug: string): DocEntry | undefined => bySlug.get(slug);

// Resolves a symbol to a docs slug: the word itself, or the leading keyword of
// a definition's title (e.g. "chord" from "chord Cmaj").
export function docFor(word: string, title?: string): string | null {
  if (byWord.has(word)) return byWord.get(word)!;
  const head = title?.split(" ", 1)[0];
  if (head && byWord.has(head)) return byWord.get(head)!;
  if (/^[A-G][#b]?\d+$/.test(word)) return "note";
  return null;
}
