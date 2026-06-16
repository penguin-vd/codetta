interface Props {
  ready: boolean;
  playing: boolean;
  tempo: number | null;
  signature: [number, number] | null;
  noteCount: number;
  error: string | null;
  onPlay: () => void;
  onStop: () => void;
  onExport: () => void;
}

export function Transport({ ready, playing, tempo, signature, noteCount, error, onPlay, onStop, onExport }: Props) {
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
          <span className="tracking-widest">{ready ? "—" : "loading engine…"}</span>
        )}
      </div>

      <div className="flex gap-2">
        <button
          onClick={playing ? onStop : onPlay}
          disabled={disabled}
          className="inline-flex items-center gap-2 rounded-md bg-gold px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-[#2a1c06] transition hover:brightness-105 disabled:opacity-40 disabled:hover:brightness-100"
        >
          <span className="text-[10px]">{playing ? "■" : "▶"}</span>
          {playing ? "Stop" : "Play"}
        </button>
        <button
          onClick={onExport}
          disabled={disabled}
          className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-cream transition hover:border-gold/50 hover:text-gold disabled:opacity-40"
        >
          <span className="text-[10px]">⤓</span>
          MIDI
        </button>
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
