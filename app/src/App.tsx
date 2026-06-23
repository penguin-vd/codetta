import { BookOpen, Check, Eye, Share2 } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { defaultInstrument, Engine } from './audio.ts';
import { Editor } from './components/Editor.tsx';
import { Header } from './components/Header.tsx';
import { PianoRoll } from './components/PianoRoll.tsx';
import { TrackRail } from './components/TrackRail.tsx';
import { Transport } from './components/Transport.tsx';
import { useRoute } from './router.ts';
import { shareLink } from './share.ts';
import type { Song } from './types.ts';
import { CompileError, compileMidi, compileSong, preloadWasm } from './wasm.ts';

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

const STORAGE_KEY = 'codetta-source';
const INSTRUMENTS_KEY = 'codetta-instruments';

function getInitialSource(): string {
    return localStorage.getItem(STORAGE_KEY) ?? SAMPLE;
}

function getStoredInstruments(): Record<string, string> {
    try {
        const raw = localStorage.getItem(INSTRUMENTS_KEY);
        return raw ? JSON.parse(raw) : {};
    } catch {
        return {};
    }
}

export function App() {
    const route = useRoute();
    const isShared = route.name === 'shared';

    // A shared link carries its source in the URL and must never touch the
    // visitor's own stored draft — seed from the link, persist nothing.
    const [source, setSource] = useState(() =>
        route.name === 'shared' ? route.source : getInitialSource()
    );
    const [song, setSong] = useState<Song | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [ready, setReady] = useState(false);
    const [playing, setPlaying] = useState(false);
    const [instruments, setInstruments] = useState<Record<string, string>>(getStoredInstruments);
    const [muted, setMuted] = useState<Set<string>>(new Set());
    const [soloed, setSoloed] = useState<Set<string>>(new Set());
    const [looping, setLooping] = useState(false);

    useEffect(() => {
        if (isShared) return;
        const id = setTimeout(() => localStorage.setItem(STORAGE_KEY, source), 400);
        return () => clearTimeout(id);
    }, [source, isShared]);

    useEffect(() => {
        if (isShared) return;
        localStorage.setItem(INSTRUMENTS_KEY, JSON.stringify(instruments));
    }, [instruments, isShared]);

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
            song
                ? song.tracks.map(
                      (t) => !muted.has(t.name) && (soloed.size === 0 || soloed.has(t.name))
                  )
                : [],
        [song, muted, soloed]
    );

    useEffect(() => {
        if (playing) engine.setAudible(audible);
    }, [audible, playing, engine]);

    const noteCount = song ? song.tracks.reduce((sum, t) => sum + t.notes.length, 0) : 0;

    async function play() {
        if (!song) return;
        const ids = song.tracks.map((t) => instruments[t.name] ?? defaultInstrument(t.name));
        await engine.play(song, ids, audible, looping, () => setPlaying(false));
        setPlaying(true);
    }

    useEffect(() => {
        if (playing) engine.setLoop(looping, song ?? undefined);
    }, [looping, playing, engine, song]);

    function stop() {
        engine.stop();
        setPlaying(false);
    }

    const [exporting, setExporting] = useState(false);

    async function exportMidi() {
        try {
            const bytes = await compileMidi(source);
            const url = URL.createObjectURL(
                new Blob([bytes.slice().buffer], { type: 'audio/midi' })
            );
            const a = document.createElement('a');
            a.href = url;
            a.download = 'song.mid';
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
            const a = document.createElement('a');
            a.href = url;
            a.download = 'song.wav';
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

    const [copied, setCopied] = useState(false);

    async function share() {
        try {
            await navigator.clipboard.writeText(shareLink(source));
            setCopied(true);
            setTimeout(() => setCopied(false), 1600);
        } catch {
            /* clipboard blocked; nothing to surface */
        }
    }

    // Promote a shared song to the visitor's own editable draft.
    function makeCopy() {
        localStorage.setItem(STORAGE_KEY, source);
        localStorage.setItem(INSTRUMENTS_KEY, JSON.stringify(instruments));
        window.location.hash = '#/';
    }

    return (
        <div className="flex h-screen flex-col">
            <Header
                subtitle="music, compiled"
                actions={
                    <>
                        <button
                            type="button"
                            onClick={share}
                            disabled={!source.trim()}
                            className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-cream transition hover:border-gold/50 hover:text-gold disabled:opacity-40"
                        >
                            {copied ? <Check size={14} /> : <Share2 size={14} />}
                            {copied ? 'Copied' : 'Share'}
                        </button>
                        <Transport
                            ready={ready}
                            playing={playing}
                            looping={looping}
                            tempo={song?.header.tempo ?? null}
                            signature={song?.header.timeSignature ?? null}
                            noteCount={noteCount}
                            error={error}
                            exporting={exporting}
                            onPlay={play}
                            onStop={stop}
                            onToggleLoop={() => setLooping((l) => !l)}
                            onExportMidi={exportMidi}
                            onExportWav={exportWav}
                        />
                        <a
                            href="#/docs"
                            className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-cream transition hover:border-gold/50 hover:text-gold"
                        >
                            <BookOpen size={14} />
                            Docs
                        </a>
                    </>
                }
            />

            {isShared && (
                <div className="flex items-center justify-between gap-3 border-b border-gold/30 bg-gold/10 px-6 py-2 font-mono text-xs text-cream">
                    <span className="inline-flex items-center gap-2 text-dim">
                        <Eye size={14} className="text-gold" />
                        Viewing a shared song — your own draft is untouched.
                    </span>
                    <button
                        type="button"
                        onClick={makeCopy}
                        className="rounded-md border border-gold/40 bg-gold/10 px-3 py-1.5 font-semibold uppercase tracking-wider text-gold transition hover:bg-gold/20"
                    >
                        Make a copy to edit
                    </button>
                </div>
            )}

            <main className="grid min-h-0 flex-1 grid-cols-[minmax(320px,36%)_1fr]">
                <section className="min-h-0 overflow-hidden border-r border-line">
                    <Editor value={source} onChange={setSource} />
                </section>

                <section className="grid min-h-0 grid-rows-[1fr_auto]">
                    <PianoRoll song={song} engine={engine} playing={playing} audible={audible} />
                    {song && song.tracks.length > 0 && (
                        <TrackRail
                            tracks={song.tracks}
                            instruments={instruments}
                            muted={muted}
                            soloed={soloed}
                            onInstrument={(name, id) =>
                                setInstruments((prev) => ({ ...prev, [name]: id }))
                            }
                            onToggleMute={(name) => setMuted((m) => toggle(m, name))}
                            onToggleSolo={(name) => setSoloed((s) => toggle(s, name))}
                        />
                    )}
                </section>
            </main>
        </div>
    );
}
