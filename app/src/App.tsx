import { useEffect, useMemo, useRef, useState } from "react";
import { Editor } from "./components/Editor.tsx";
import { Transport } from "./components/Transport.tsx";
import { PianoRoll } from "./components/PianoRoll.tsx";
import { TrackRail } from "./components/TrackRail.tsx";
import { Engine, defaultInstrument } from "./audio.ts";
import { compileSong, compileMidi, preloadWasm, CompileError } from "./wasm.ts";
import type { Song } from "./types.ts";

const SAMPLE = `tempo 100
time_signature 4/4

chord Cmaj = [B3 C4 E4 G3]
chord Dmin = [F4 A3 C4 D4]

phrase bass =
  C2.quarter C3.quarter C2.quarter C3.quarter
  D2.quarter D3.quarter D2.quarter D3.quarter

section loop =
  track chords: Cmaj.whole Dmin.whole
  track bass:   bass

song =
  loop * 4
`;

function getInitialTheme(): boolean {
  const stored = localStorage.getItem("codetta-theme");
  if (stored) return stored === "dark";
  return true;
}

export function App() {
  const [source, setSource] = useState(SAMPLE);
  const [song, setSong] = useState<Song | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [instruments, setInstruments] = useState<Record<string, string>>({});
  const [muted, setMuted] = useState<Set<string>>(new Set());
  const [soloed, setSoloed] = useState<Set<string>>(new Set());
  const [dark, setDark] = useState(getInitialTheme);

  useEffect(() => {
    document.documentElement.classList.toggle("light", !dark);
    localStorage.setItem("codetta-theme", dark ? "dark" : "light");
  }, [dark]);

  const engineRef = useRef<Engine | null>(null);
  if (!engineRef.current) engineRef.current = new Engine();
  const engine = engineRef.current;

  useEffect(() => {
    preloadWasm().then(() => setReady(true));
  }, []);

  // Compile on every edit; the WASM round-trip is sub-millisecond.
  useEffect(() => {
    let cancelled = false;
    const handle = setTimeout(async () => {
      try {
        const next = await compileSong(source);
        if (!cancelled) {
          setSong(next);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) setError(e instanceof CompileError ? e.message : String(e));
      }
    }, 160);
    return () => {
      cancelled = true;
      clearTimeout(handle);
    };
  }, [source]);

  // A new score invalidates playback and gets default voices for new tracks.
  useEffect(() => {
    if (!song) return;
    engine.stop();
    setPlaying(false);
    setInstruments((prev) => {
      const next = { ...prev };
      for (const track of song.tracks) {
        if (!(track.name in next)) next[track.name] = defaultInstrument(track.name);
      }
      return next;
    });
  }, [song, engine]);

  const audible = useMemo(
    () =>
      song ? song.tracks.map((t) => !muted.has(t.name) && (soloed.size === 0 || soloed.has(t.name))) : [],
    [song, muted, soloed],
  );

  useEffect(() => {
    if (playing) engine.setAudible(audible);
  }, [audible, playing, engine]);

  const noteCount = song ? song.tracks.reduce((sum, t) => sum + t.notes.length, 0) : 0;

  async function play() {
    if (!song) return;
    const ids = song.tracks.map((t) => instruments[t.name] ?? defaultInstrument(t.name));
    await engine.play(song, ids, audible, () => setPlaying(false));
    setPlaying(true);
  }

  function stop() {
    engine.stop();
    setPlaying(false);
  }

  const [exporting, setExporting] = useState(false);

  async function exportMidi() {
    try {
      const bytes = await compileMidi(source);
      const url = URL.createObjectURL(new Blob([bytes.slice().buffer], { type: "audio/midi" }));
      const a = document.createElement("a");
      a.href = url;
      a.download = "song.mid";
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      /* surfaced by the live compile */
    }
  }

  async function exportWav() {
    if (!song || exporting) return;
    setExporting(true);
    try {
      const ids = song.tracks.map((t) => instruments[t.name] ?? defaultInstrument(t.name));
      const blob = await engine.renderWav(song, ids, audible);
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "song.wav";
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      /* surfaced by the live compile */
    } finally {
      setExporting(false);
    }
  }

  const toggle = (set: Set<string>, name: string) => {
    const next = new Set(set);
    next.has(name) ? next.delete(name) : next.add(name);
    return next;
  };

  return (
    <div className="grid h-screen grid-rows-[auto_1fr]">
      <header className="flex items-center justify-between border-b border-line px-6 py-3">
        <div className="flex items-baseline gap-3">
          <span className="font-serif text-2xl font-semibold text-cream">Codetta</span>
          <span className="font-mono text-[10px] uppercase tracking-[0.25em] text-dim">music, compiled</span>
        </div>
        <div className="flex items-center gap-3">
          <Transport
            ready={ready}
            playing={playing}
            tempo={song?.header.tempo ?? null}
            signature={song?.header.timeSignature ?? null}
            noteCount={noteCount}
            error={error}
            exporting={exporting}
            onPlay={play}
            onStop={stop}
            onExportMidi={exportMidi}
            onExportWav={exportWav}
          />
          <button
            onClick={() => setDark((d) => !d)}
            className="grid h-9 w-9 place-items-center rounded-md border border-line bg-raise text-sm text-dim transition hover:border-gold/50 hover:text-gold"
            title={dark ? "Switch to light mode" : "Switch to dark mode"}
          >
            {dark ? "☀" : "☾"}
          </button>
          <a
            href="#/docs"
            className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-cream transition hover:border-gold/50 hover:text-gold"
          >
            <span className="text-[10px]">?</span>
            Docs
          </a>
        </div>
      </header>

      <main className="grid min-h-0 grid-cols-[minmax(320px,36%)_1fr]">
        <section className="flex min-h-0 flex-col border-r border-line">
          <div className="flex items-center gap-2 border-b border-line px-5 py-2.5 font-mono text-[11px] text-dim">
            <span className="h-[7px] w-[7px] rounded-full bg-gold" />
            score.coda
          </div>
          <div className="min-h-0 flex-1 overflow-hidden">
            <Editor value={source} onChange={setSource} dark={dark} />
          </div>
        </section>

        <section className="grid min-h-0 grid-rows-[1fr_auto]">
          <PianoRoll song={song} engine={engine} playing={playing} audible={audible} dark={dark} />
          {song && song.tracks.length > 0 && (
            <TrackRail
              tracks={song.tracks}
              instruments={instruments}
              muted={muted}
              soloed={soloed}
              onInstrument={(name, id) => setInstruments((prev) => ({ ...prev, [name]: id }))}
              onToggleMute={(name) => setMuted((m) => toggle(m, name))}
              onToggleSolo={(name) => setSoloed((s) => toggle(s, name))}
            />
          )}
        </section>
      </main>
    </div>
  );
}
