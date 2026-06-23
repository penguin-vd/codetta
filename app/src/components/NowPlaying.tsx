import { useEffect, useRef, useState } from 'react';
import type { Engine } from '../audio.ts';
import { secondsPerTick, songSeconds } from '../audio.ts';
import { trackColor } from '../palette.ts';
import type { Song } from '../types.ts';

interface Props {
    song: Song | null;
    engine: Engine;
    playing: boolean;
    audible: boolean[];
}

// A lightweight stand-in for the piano roll on phones: a progress bar plus a
// dot per track that pulses while that track has a note sounding. Decorative —
// it just gives the playback some motion without the roll's scroll gestures.
export function NowPlaying({ song, engine, playing, audible }: Props) {
    const [progress, setProgress] = useState(0);
    const [active, setActive] = useState<boolean[]>([]);
    const rafRef = useRef(0);

    const total = song ? songSeconds(song) : 0;

    useEffect(() => {
        if (!playing || !song || total === 0) {
            setProgress(0);
            setActive([]);
            return;
        }
        const spt = secondsPerTick(song);
        const tick = () => {
            const sec = engine.seconds;
            setProgress(Math.min(sec / total, 1));
            const at = sec / spt;
            setActive(
                song.tracks.map((t) =>
                    t.notes.some((n) => at >= n.ticks && at < n.ticks + n.durationTicks)
                )
            );
            rafRef.current = requestAnimationFrame(tick);
        };
        rafRef.current = requestAnimationFrame(tick);
        return () => cancelAnimationFrame(rafRef.current);
    }, [playing, song, total, engine]);

    if (!song || song.tracks.length === 0) return null;

    return (
        <div className="flex flex-col gap-3 border-t border-line bg-panel px-4 py-3">
            <div className="flex items-center gap-3">
                {song.tracks.map((track, i) => {
                    const on = audible[i] ?? true;
                    const lit = playing && on && active[i];
                    return (
                        <div key={track.name} className="flex min-w-0 items-center gap-1.5">
                            <span
                                className="h-2.5 w-2.5 shrink-0 rounded-full transition-all duration-100"
                                style={{
                                    background: trackColor(i),
                                    opacity: lit ? 1 : on ? 0.35 : 0.12,
                                    transform: lit ? 'scale(1.25)' : 'scale(1)',
                                }}
                            />
                            <span className="truncate font-mono text-[11px] text-dim">
                                {track.name}
                            </span>
                        </div>
                    );
                })}
            </div>
            <div className="h-1 overflow-hidden rounded-full bg-raise">
                <div
                    className="h-full rounded-full bg-gold transition-[width] duration-75 ease-linear"
                    style={{ width: `${progress * 100}%` }}
                />
            </div>
        </div>
    );
}
