import { Menu } from '@base-ui/react/menu';
import {
    BookOpen,
    Check,
    ChevronDown,
    Download,
    Eye,
    Play,
    Repeat,
    Share2,
    Sliders,
    Square,
} from 'lucide-react';
import { useState } from 'react';
import type { Engine } from '../audio.ts';
import type { Song, Track } from '../types.ts';
import { Editor } from './Editor.tsx';
import { NowPlaying } from './NowPlaying.tsx';
import { ThemeToggle } from './ThemeToggle.tsx';
import { TrackRail } from './TrackRail.tsx';

interface Props {
    source: string;
    onSource: (value: string) => void;
    song: Song | null;
    engine: Engine;
    ready: boolean;
    playing: boolean;
    looping: boolean;
    error: string | null;
    noteCount: number;
    exporting: boolean;
    audible: boolean[];
    onPlay: () => void;
    onStop: () => void;
    onToggleLoop: () => void;
    onExportMidi: () => void;
    onExportWav: () => void;
    onShare: () => void;
    copied: boolean;
    isShared: boolean;
    onMakeCopy: () => void;
    instruments: Record<string, string>;
    muted: Set<string>;
    soloed: Set<string>;
    onInstrument: (name: string, id: string) => void;
    onToggleMute: (name: string) => void;
    onToggleSolo: (name: string) => void;
}

export function MobileApp(props: Props) {
    const {
        source,
        onSource,
        song,
        engine,
        ready,
        playing,
        looping,
        error,
        noteCount,
        exporting,
        audible,
        onPlay,
        onStop,
        onToggleLoop,
        onExportMidi,
        onExportWav,
        onShare,
        copied,
        isShared,
        onMakeCopy,
    } = props;

    const [mixOpen, setMixOpen] = useState(false);
    const disabled = !ready || noteCount === 0;
    const tracks: Track[] = song?.tracks ?? [];

    return (
        <div className="flex h-[100dvh] flex-col">
            <header className="flex items-center justify-between border-b border-line px-4 py-2.5">
                <div className="flex min-w-0 flex-col">
                    <span className="font-serif text-xl font-semibold leading-none text-cream">
                        Codetta
                    </span>
                    <span className="mt-1 font-mono text-[10px] uppercase tracking-wider text-dim">
                        {error ? (
                            <span className="text-coral">won't compile</span>
                        ) : song?.header.tempo != null ? (
                            <>
                                {song.header.tempo} bpm · {song.header.timeSignature[0]}/
                                {song.header.timeSignature[1]} · {noteCount} notes
                            </>
                        ) : (
                            <span>{ready ? 'music, compiled' : 'loading engine…'}</span>
                        )}
                    </span>
                </div>
                <div className="flex shrink-0 items-center gap-1.5">
                    <IconBtn onClick={onShare} disabled={!source.trim()} label="Share">
                        {copied ? <Check size={16} /> : <Share2 size={16} />}
                    </IconBtn>
                    <a
                        href="#/docs"
                        className="grid h-9 w-9 place-items-center rounded-md border border-line bg-raise text-cream transition active:border-gold/50"
                        aria-label="Docs"
                    >
                        <BookOpen size={16} />
                    </a>
                    <ThemeToggle />
                </div>
            </header>

            {isShared && (
                <div className="flex items-center justify-between gap-2 border-b border-gold/30 bg-gold/10 px-4 py-2 font-mono text-[11px] text-cream">
                    <span className="inline-flex min-w-0 items-center gap-2 text-dim">
                        <Eye size={13} className="shrink-0 text-gold" />
                        <span className="truncate">Viewing a shared song</span>
                    </span>
                    <button
                        type="button"
                        onClick={onMakeCopy}
                        className="shrink-0 rounded-md border border-gold/40 bg-gold/10 px-2.5 py-1 font-semibold uppercase tracking-wider text-gold active:bg-gold/20"
                    >
                        Copy to edit
                    </button>
                </div>
            )}

            <section className="min-h-0 flex-1 overflow-hidden">
                <Editor value={source} onChange={onSource} />
            </section>

            <NowPlaying song={song} engine={engine} playing={playing} audible={audible} />

            {tracks.length > 0 && (
                <>
                    <button
                        type="button"
                        onClick={() => setMixOpen((o) => !o)}
                        className="flex items-center justify-between border-t border-line px-4 py-2.5 font-mono text-[11px] uppercase tracking-wider text-dim"
                    >
                        <span className="inline-flex items-center gap-2">
                            <Sliders size={14} />
                            Mix · {tracks.length} {tracks.length === 1 ? 'track' : 'tracks'}
                        </span>
                        <ChevronDown
                            size={16}
                            className={`transition-transform ${mixOpen ? 'rotate-180' : ''}`}
                        />
                    </button>
                    {mixOpen && (
                        <TrackRail
                            tracks={tracks}
                            instruments={props.instruments}
                            muted={props.muted}
                            soloed={props.soloed}
                            onInstrument={props.onInstrument}
                            onToggleMute={props.onToggleMute}
                            onToggleSolo={props.onToggleSolo}
                        />
                    )}
                </>
            )}

            <div className="flex items-center gap-2 border-t border-line bg-panel px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
                <button
                    type="button"
                    onClick={onToggleLoop}
                    className={`grid h-12 w-12 shrink-0 place-items-center rounded-lg border transition ${
                        looping
                            ? 'border-gold/50 bg-gold/10 text-gold'
                            : 'border-line bg-raise text-dim'
                    }`}
                    aria-label={looping ? 'Looping' : 'Loop'}
                >
                    <Repeat size={18} />
                </button>
                <button
                    type="button"
                    onClick={playing ? onStop : onPlay}
                    disabled={disabled}
                    className="flex h-12 flex-1 items-center justify-center gap-2 rounded-lg bg-gold font-mono text-sm font-semibold uppercase tracking-wider text-[#2a1c06] transition active:brightness-105 disabled:opacity-40"
                >
                    {playing ? (
                        <Square size={16} fill="currentColor" />
                    ) : (
                        <Play size={16} fill="currentColor" />
                    )}
                    {playing ? 'Stop' : 'Play'}
                </button>
                <Menu.Root>
                    <Menu.Trigger
                        disabled={disabled || exporting}
                        className="grid h-12 w-12 shrink-0 place-items-center rounded-lg border border-line bg-raise text-cream transition disabled:opacity-40"
                        aria-label="Export"
                    >
                        <Download size={18} />
                    </Menu.Trigger>
                    <Menu.Portal>
                        <Menu.Positioner side="top" align="end" sideOffset={4}>
                            <Menu.Popup className="min-w-[140px] rounded-md border border-line bg-panel shadow-lg">
                                <Menu.Item
                                    className="flex w-full items-center gap-2 px-4 py-3 text-left font-mono text-xs uppercase tracking-wider text-cream data-[highlighted]:bg-raise"
                                    onSelect={onExportMidi}
                                >
                                    MIDI
                                </Menu.Item>
                                <Menu.Item
                                    className="flex w-full items-center gap-2 px-4 py-3 text-left font-mono text-xs uppercase tracking-wider text-cream data-[highlighted]:bg-raise"
                                    onSelect={onExportWav}
                                >
                                    {exporting ? 'Exporting…' : 'WAV'}
                                </Menu.Item>
                            </Menu.Popup>
                        </Menu.Positioner>
                    </Menu.Portal>
                </Menu.Root>
            </div>
        </div>
    );
}

function IconBtn({
    onClick,
    disabled,
    label,
    children,
}: {
    onClick: () => void;
    disabled?: boolean;
    label: string;
    children: React.ReactNode;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            disabled={disabled}
            aria-label={label}
            className="grid h-9 w-9 place-items-center rounded-md border border-line bg-raise text-cream transition active:border-gold/50 disabled:opacity-40"
        >
            {children}
        </button>
    );
}
