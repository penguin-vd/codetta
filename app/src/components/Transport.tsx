import { Menu } from '@base-ui/react/menu';
import { ChevronDown, Download, Play, Repeat, Square } from 'lucide-react';

interface Props {
    ready: boolean;
    playing: boolean;
    looping: boolean;
    tempo: number | null;
    signature: [number, number] | null;
    noteCount: number;
    error: string | null;
    exporting: boolean;
    onPlay: () => void;
    onStop: () => void;
    onToggleLoop: () => void;
    onExportMidi: () => void;
    onExportWav: () => void;
}

export function Transport({
    ready,
    playing,
    looping,
    tempo,
    signature,
    noteCount,
    error,
    exporting,
    onPlay,
    onStop,
    onToggleLoop,
    onExportMidi,
    onExportWav,
}: Props) {
    const disabled = !ready || noteCount === 0;

    return (
        <div className="flex items-center gap-6">
            <div className="flex items-center gap-3 font-mono text-[11px] uppercase tracking-wider text-dim">
                {error ? (
                    <span className="text-coral">won't compile</span>
                ) : tempo != null ? (
                    <>
                        <Stat value={tempo} unit="bpm" />
                        <Divider />
                        <span>
                            <em className="not-italic font-bold text-cream">{signature?.[0]}</em>/
                            <em className="not-italic font-bold text-cream">{signature?.[1]}</em>
                        </span>
                        <Divider />
                        <Stat value={noteCount} unit="notes" />
                    </>
                ) : (
                    <span className="tracking-widest">{ready ? '—' : 'loading engine…'}</span>
                )}
            </div>

            <div className="flex gap-2">
                <button
                    type="button"
                    onClick={playing ? onStop : onPlay}
                    disabled={disabled}
                    className="inline-flex items-center gap-2 rounded-md bg-gold px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-[#2a1c06] transition hover:brightness-105 disabled:opacity-40 disabled:hover:brightness-100"
                >
                    {playing ? (
                        <Square size={12} fill="currentColor" />
                    ) : (
                        <Play size={12} fill="currentColor" />
                    )}
                    {playing ? 'Stop' : 'Play'}
                </button>
                <button
                    type="button"
                    onClick={onToggleLoop}
                    className={`inline-flex items-center rounded-md border px-2.5 py-2 transition ${
                        looping
                            ? 'border-gold/50 bg-gold/10 text-gold'
                            : 'border-line bg-raise text-dim hover:border-gold/30 hover:text-cream'
                    }`}
                    title={looping ? 'Looping' : 'Loop'}
                >
                    <Repeat size={14} />
                </button>
                <Menu.Root>
                    <Menu.Trigger
                        disabled={disabled || exporting}
                        className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-cream transition hover:border-gold/50 hover:text-gold disabled:opacity-40"
                    >
                        <Download size={14} />
                        {exporting ? 'Exporting…' : 'Export'}
                        <ChevronDown size={12} />
                    </Menu.Trigger>
                    <Menu.Portal>
                        <Menu.Positioner side="bottom" align="end" sideOffset={4}>
                            <Menu.Popup className="min-w-[140px] rounded-md border border-line bg-panel shadow-lg">
                                <Menu.Item
                                    className="flex w-full items-center gap-2 px-4 py-2.5 text-left font-mono text-xs uppercase tracking-wider text-cream transition hover:bg-raise data-[highlighted]:bg-raise"
                                    onSelect={onExportMidi}
                                >
                                    MIDI
                                </Menu.Item>
                                <Menu.Item
                                    className="flex w-full items-center gap-2 px-4 py-2.5 text-left font-mono text-xs uppercase tracking-wider text-cream transition hover:bg-raise data-[highlighted]:bg-raise"
                                    onSelect={onExportWav}
                                >
                                    WAV
                                </Menu.Item>
                            </Menu.Popup>
                        </Menu.Positioner>
                    </Menu.Portal>
                </Menu.Root>
            </div>
        </div>
    );
}

const Stat = ({ value, unit }: { value: number; unit: string }) => (
    <span>
        <em className="not-italic font-bold text-cream">{value}</em> {unit}
    </span>
);

const Divider = () => <span className="h-3 w-px bg-line" />;
