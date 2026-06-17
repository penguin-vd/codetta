import { useEffect, useRef, useState } from "react";

interface Props {
  ready: boolean;
  playing: boolean;
  tempo: number | null;
  signature: [number, number] | null;
  noteCount: number;
  error: string | null;
  exporting: boolean;
  onPlay: () => void;
  onStop: () => void;
  onExportMidi: () => void;
  onExportWav: () => void;
}

export function Transport({ ready, playing, tempo, signature, noteCount, error, exporting, onPlay, onStop, onExportMidi, onExportWav }: Props) {
  const disabled = !ready || noteCount === 0;
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [open]);

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
        <div ref={menuRef} className="relative">
          <button
            onClick={() => setOpen((o) => !o)}
            disabled={disabled || exporting}
            className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-cream transition hover:border-gold/50 hover:text-gold disabled:opacity-40"
          >
            <span className="text-[10px]">⤓</span>
            {exporting ? "Exporting…" : "Export"}
          </button>
          {open && (
            <div className="absolute right-0 top-full z-10 mt-1 min-w-[140px] rounded-md border border-line bg-panel shadow-lg">
              <button
                onClick={() => { setOpen(false); onExportMidi(); }}
                className="flex w-full items-center gap-2 px-4 py-2.5 text-left font-mono text-xs uppercase tracking-wider text-cream transition hover:bg-raise"
              >
                MIDI
              </button>
              <button
                onClick={() => { setOpen(false); onExportWav(); }}
                className="flex w-full items-center gap-2 px-4 py-2.5 text-left font-mono text-xs uppercase tracking-wider text-cream transition hover:bg-raise"
              >
                WAV
              </button>
            </div>
          )}
        </div>
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
