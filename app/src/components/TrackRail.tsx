import { INSTRUMENTS } from '../audio.ts';
import { trackColor } from '../palette.ts';
import type { Track } from '../types.ts';

interface Props {
    tracks: Track[];
    instruments: Record<string, string>;
    muted: Set<string>;
    soloed: Set<string>;
    onInstrument: (name: string, id: string) => void;
    onToggleMute: (name: string) => void;
    onToggleSolo: (name: string) => void;
}

export function TrackRail({
    tracks,
    instruments,
    muted,
    soloed,
    onInstrument,
    onToggleMute,
    onToggleSolo,
}: Props) {
    return (
        <div className="flex gap-3 overflow-x-auto border-t border-line px-4 py-3">
            {tracks.map((track, i) => (
                <div
                    key={track.name}
                    className="relative flex min-w-[264px] items-center gap-2.5 rounded-lg border border-line bg-panel py-2.5 pl-4 pr-3"
                >
                    <span
                        className="absolute inset-y-2.5 left-0 w-[3px] rounded"
                        style={{ background: trackColor(i) }}
                    />
                    <div className="flex min-w-0 flex-col">
                        <span className="truncate font-serif text-[15px] font-medium text-cream">
                            {track.name}
                        </span>
                        <span className="font-mono text-[10px] text-dim">
                            {track.notes.length} notes
                        </span>
                    </div>

                    <select
                        value={instruments[track.name] ?? INSTRUMENTS[0].id}
                        onChange={(e) => onInstrument(track.name, e.target.value)}
                        className="ml-auto cursor-pointer rounded-md border border-line bg-raise px-2.5 py-1.5 text-xs font-semibold text-cream hover:border-dim"
                    >
                        {INSTRUMENTS.map((inst) => (
                            <option key={inst.id} value={inst.id}>
                                {inst.label}
                            </option>
                        ))}
                    </select>

                    <div className="flex gap-1">
                        <Toggle
                            active={muted.has(track.name)}
                            activeClass="bg-coral text-[#1a0c0e]"
                            onClick={() => onToggleMute(track.name)}
                        >
                            M
                        </Toggle>
                        <Toggle
                            active={soloed.has(track.name)}
                            activeClass="bg-gold text-[#2a1c06]"
                            onClick={() => onToggleSolo(track.name)}
                        >
                            S
                        </Toggle>
                    </div>
                </div>
            ))}
        </div>
    );
}

function Toggle({
    active,
    activeClass,
    onClick,
    children,
}: {
    active: boolean;
    activeClass: string;
    onClick: () => void;
    children: React.ReactNode;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className={`h-[26px] w-[26px] rounded-md border font-mono text-[11px] font-bold transition ${
                active
                    ? `${activeClass} border-transparent`
                    : 'border-line bg-raise text-dim hover:text-cream'
            }`}
        >
            {children}
        </button>
    );
}
