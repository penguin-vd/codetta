import { useCallback, useEffect, useRef, useState } from "react";
import type { Song } from "../types.ts";
import type { Engine } from "../audio.ts";
import { secondsPerTick } from "../audio.ts";
import { trackColor } from "../palette.ts";

const GUTTER = 46;
const RULER = 26;
const BLACK_KEYS = new Set([1, 3, 6, 8, 10]);
const MAX_ZOOM = 48;

interface Props {
  song: Song | null;
  engine: Engine;
  playing: boolean;
  audible: boolean[];
  dark: boolean;
}

const noteName = (midi: number) =>
  `${["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][midi % 12]}${Math.floor(midi / 12) - 1}`;

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

const velLabel = (v: number): string => {
  const midi = Math.round(v * 127);
  if (midi <= 20) return "ppp";
  if (midi <= 40) return "pp";
  if (midi <= 56) return "p";
  if (midi <= 72) return "mp";
  if (midi <= 88) return "mf";
  if (midi <= 104) return "f";
  if (midi <= 120) return "ff";
  return "fff";
};

const DARK_CANVAS = {
  bg: "#100e0b",
  blackKey: "rgba(0,0,0,0.2)",
  octaveLine: "rgba(236,229,216,0.07)",
  barLine: "rgba(236,229,216,0.12)",
  beatLine: "rgba(236,229,216,0.04)",
  textDim: "rgba(151,143,129,0.55)",
  textFaint: "rgba(151,143,129,0.5)",
  textMed: "rgba(151,143,129,0.6)",
  border: "rgba(44,39,32,1)",
  playhead: "#e0a13c",
};

const LIGHT_CANVAS = {
  bg: "#f5f1eb",
  blackKey: "rgba(0,0,0,0.06)",
  octaveLine: "rgba(42,37,32,0.1)",
  barLine: "rgba(42,37,32,0.16)",
  beatLine: "rgba(42,37,32,0.06)",
  textDim: "rgba(122,114,104,0.7)",
  textFaint: "rgba(122,114,104,0.5)",
  textMed: "rgba(122,114,104,0.8)",
  border: "rgba(208,201,189,1)",
  playhead: "#c48a2a",
};

export function PianoRoll({ song, engine, playing, audible, dark }: Props) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rafRef = useRef(0);
  const scrollRef = useRef(0);
  const dragRef = useRef<{ x: number; scroll: number } | null>(null);
  const [zoom, setZoom] = useState(1);
  const zoomRef = useRef(1);
  zoomRef.current = zoom;
  const playingRef = useRef(playing);
  playingRef.current = playing;
  const layoutRef = useRef<{ lo: number; hi: number; px: number; scroll: number; rowH: number; totalTicks: number } | null>(null);
  const [tooltip, setTooltip] = useState<{ x: number; y: number; text: string } | null>(null);

  const draw = useCallback(
    (playheadSec: number | null) => {
      const canvas = canvasRef.current;
      const wrap = wrapRef.current;
      if (!canvas || !wrap) return;
      const c = dark ? DARK_CANVAS : LIGHT_CANVAS;

      const dpr = window.devicePixelRatio || 1;
      const w = wrap.clientWidth;
      const h = wrap.clientHeight;
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
      const ctx = canvas.getContext("2d")!;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      if (!song) return;

      let lo = 127;
      let hi = 0;
      let totalTicks = 0;
      for (const track of song.tracks) {
        for (const n of track.notes) {
          lo = Math.min(lo, n.midi);
          hi = Math.max(hi, n.midi);
          totalTicks = Math.max(totalTicks, n.ticks + n.durationTicks);
        }
      }
      if (totalTicks === 0) {
        ctx.fillStyle = c.textFaint;
        ctx.font = "italic 15px var(--font-serif), serif";
        ctx.fillText("an empty score", GUTTER + 16, RULER + 30);
        return;
      }
      lo -= 1;
      hi += 1;

      const plotW = w - GUTTER;
      const usable = plotW - 14;
      const rowH = (h - RULER) / (hi - lo + 1);
      const fitPx = usable / totalTicks;
      const px = fitPx * zoomRef.current;
      const maxScroll = Math.max(0, totalTicks * px - usable);
      scrollRef.current = clamp(scrollRef.current, 0, maxScroll);
      const scroll = scrollRef.current;
      const yOf = (midi: number) => RULER + (hi - midi) * rowH;
      const xOf = (tick: number) => GUTTER + tick * px - scroll;

      const [num, den] = song.header.timeSignature;
      const ticksPerBeat = (song.header.ppq * 4) / den;
      const ticksPerBar = ticksPerBeat * num;

      // Plot area (clipped so nothing bleeds into the rulers).
      ctx.save();
      ctx.beginPath();
      ctx.rect(GUTTER, RULER, plotW, h - RULER);
      ctx.clip();

      for (let midi = lo; midi <= hi; midi++) {
        if (BLACK_KEYS.has(((midi % 12) + 12) % 12)) {
          ctx.fillStyle = c.blackKey;
          ctx.fillRect(GUTTER, yOf(midi), plotW, rowH);
        }
        if (midi % 12 === 0) {
          ctx.strokeStyle = c.octaveLine;
          ctx.beginPath();
          ctx.moveTo(GUTTER, yOf(midi) + rowH);
          ctx.lineTo(w, yOf(midi) + rowH);
          ctx.stroke();
        }
      }

      for (let tick = 0; tick <= totalTicks + 1; tick += ticksPerBeat) {
        const x = xOf(tick);
        if (x < GUTTER || x > w) continue;
        const isBar = Math.round(tick) % Math.round(ticksPerBar) === 0;
        ctx.strokeStyle = isBar ? c.barLine : c.beatLine;
        ctx.beginPath();
        ctx.moveTo(x, RULER);
        ctx.lineTo(x, h);
        ctx.stroke();
      }

      song.tracks.forEach((track, i) => {
        ctx.fillStyle = trackColor(i);
        const on = audible[i] ?? true;
        for (const n of track.notes) {
          const x = xOf(n.ticks);
          const bw = Math.max(xOf(n.ticks + n.durationTicks) - x - 1.5, 2);
          if (x + bw < GUTTER || x > w) continue;
          const y = yOf(n.midi) + rowH * 0.14;
          const bh = Math.max(rowH * 0.72, 2.5);
          ctx.globalAlpha = (on ? 1 : 0.16) * (0.15 + 0.85 * n.velocity);
          roundRect(ctx, x, y, bw, bh, Math.min(2.5, bh / 2));
          ctx.fill();
        }
      });
      ctx.globalAlpha = 1;
      layoutRef.current = { lo, hi, px, scroll, rowH, totalTicks };

      if (playheadSec != null) {
        const x = xOf(playheadSec / secondsPerTick(song));
        ctx.strokeStyle = c.playhead;
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(x, RULER);
        ctx.lineTo(x, h);
        ctx.stroke();
      }
      ctx.restore();

      // Top ruler with bar numbers.
      ctx.fillStyle = c.bg;
      ctx.fillRect(0, 0, w, RULER);
      ctx.fillStyle = c.textDim;
      ctx.font = "10px var(--font-mono), monospace";
      let bar = 0;
      for (let tick = 0; tick <= totalTicks + 1; tick += ticksPerBar) {
        bar++;
        const x = xOf(tick);
        if (x < GUTTER - 2 || x > w) continue;
        ctx.fillText(String(bar), x + 5, 16);
      }

      // Left gutter with octave labels.
      ctx.fillStyle = c.bg;
      ctx.fillRect(0, 0, GUTTER, h);
      ctx.fillStyle = c.textMed;
      for (let midi = lo; midi <= hi; midi++) {
        if (midi % 12 === 0) ctx.fillText(noteName(midi), 9, yOf(midi) + rowH - 3);
      }

      ctx.strokeStyle = c.border;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(GUTTER, 0);
      ctx.lineTo(GUTTER, h);
      ctx.moveTo(0, RULER);
      ctx.lineTo(w, RULER);
      ctx.stroke();
    },
    [song, audible, dark],
  );

  const redraw = useCallback(() => {
    draw(playingRef.current ? engine.seconds : null);
  }, [draw, engine]);

  // Zoom keeping the tick under `clientX` anchored in place.
  const zoomAt = useCallback(
    (clientX: number, factor: number) => {
      const wrap = wrapRef.current;
      const canvas = canvasRef.current;
      if (!wrap || !canvas || !song) return;
      const cx = clientX - canvas.getBoundingClientRect().left;
      let totalTicks = 0;
      for (const t of song.tracks) for (const n of t.notes) totalTicks = Math.max(totalTicks, n.ticks + n.durationTicks);
      if (totalTicks === 0) return;
      const usable = wrap.clientWidth - GUTTER - 14;
      const fitPx = usable / totalTicks;
      const next = clamp(zoomRef.current * factor, 1, MAX_ZOOM);
      const tickAt = (cx - GUTTER + scrollRef.current) / (fitPx * zoomRef.current);
      scrollRef.current = tickAt * fitPx * next - (cx - GUTTER);
      zoomRef.current = next;
      setZoom(next);
    },
    [song],
  );

  // Reset view on a new song.
  useEffect(() => {
    scrollRef.current = 0;
    zoomRef.current = 1;
    setZoom(1);
  }, [song]);

  // Resize + content changes.
  useEffect(() => {
    const ro = new ResizeObserver(redraw);
    if (wrapRef.current) ro.observe(wrapRef.current);
    redraw();
    return () => ro.disconnect();
  }, [redraw, zoom]);

  // Playhead animation.
  useEffect(() => {
    if (!playing) {
      draw(null);
      return;
    }
    const loop = () => {
      draw(engine.seconds);
      rafRef.current = requestAnimationFrame(loop);
    };
    rafRef.current = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(rafRef.current);
  }, [playing, draw, engine]);

  // Wheel zoom/pan and drag pan (wheel listener is non-passive to preventDefault).
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      if (e.ctrlKey || e.metaKey) {
        zoomAt(e.clientX, Math.exp(-e.deltaY * 0.0016));
      } else {
        scrollRef.current += e.deltaX !== 0 ? e.deltaX : e.deltaY;
        redraw();
      }
    };
    canvas.addEventListener("wheel", onWheel, { passive: false });
    return () => canvas.removeEventListener("wheel", onWheel);
  }, [zoomAt, redraw]);

  const onPointerDown = (e: React.PointerEvent) => {
    dragRef.current = { x: e.clientX, scroll: scrollRef.current };
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (dragRef.current) {
      scrollRef.current = dragRef.current.scroll - (e.clientX - dragRef.current.x);
      setTooltip(null);
      redraw();
      return;
    }
    if (!song || !layoutRef.current || !canvasRef.current) { setTooltip(null); return; }
    const rect = canvasRef.current.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const { hi, px, scroll, rowH } = layoutRef.current;
    const tickAt = (mx - GUTTER + scroll) / px;
    const midiAt = hi - Math.floor((my - RULER) / rowH);

    let hit: { note: string; vel: string } | null = null;
    for (const track of song.tracks) {
      for (const n of track.notes) {
        if (n.midi !== midiAt) continue;
        if (tickAt >= n.ticks && tickAt < n.ticks + n.durationTicks) {
          hit = { note: noteName(n.midi), vel: `${velLabel(n.velocity)} (${Math.round(n.velocity * 127)})` };
          break;
        }
      }
      if (hit) break;
    }
    setTooltip(hit ? { x: e.clientX - rect.left, y: e.clientY - rect.top, text: `${hit.note}  ${hit.vel}` } : null);
  };
  const endDrag = () => {
    dragRef.current = null;
  };
  const onPointerLeave = () => {
    endDrag();
    setTooltip(null);
  };

  const nudge = (factor: number) => {
    const wrap = wrapRef.current;
    if (wrap) zoomAt(wrap.getBoundingClientRect().left + wrap.clientWidth / 2, factor);
  };
  const fit = () => {
    scrollRef.current = 0;
    zoomRef.current = 1;
    setZoom(1);
  };

  return (
    <div className="group relative h-full min-h-0 overflow-hidden">
      <div
        ref={wrapRef}
        className="h-full cursor-grab active:cursor-grabbing"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerLeave={onPointerLeave}
      >
        <canvas ref={canvasRef} className="block h-full w-full" />
      </div>
      {tooltip && (
        <div
          className="pointer-events-none absolute rounded border border-line bg-panel/90 px-2 py-1 font-mono text-[11px] text-cream backdrop-blur"
          style={{ left: tooltip.x + 12, top: tooltip.y - 28 }}
        >
          {tooltip.text}
        </div>
      )}
      {song && (
        <div className="absolute right-3 top-3 flex items-center gap-1 rounded-lg border border-line bg-panel/80 px-1 py-1 opacity-0 backdrop-blur transition-opacity duration-200 group-hover:opacity-100">
          <ZoomBtn label="−" onClick={() => nudge(1 / 1.4)} disabled={zoom <= 1.001} />
          <span className="w-10 text-center font-mono text-[10px] text-dim tabular-nums">{Math.round(zoom * 100)}%</span>
          <ZoomBtn label="+" onClick={() => nudge(1.4)} disabled={zoom >= MAX_ZOOM - 0.001} />
          <button
            onClick={fit}
            disabled={zoom <= 1.001}
            className="ml-1 rounded px-2 py-1 font-mono text-[10px] uppercase tracking-wide text-dim hover:text-cream disabled:opacity-40"
          >
            Fit
          </button>
        </div>
      )}
    </div>
  );
}

function ZoomBtn({ label, onClick, disabled }: { label: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="grid h-6 w-6 place-items-center rounded font-mono text-sm text-dim hover:bg-raise hover:text-cream disabled:opacity-40 disabled:hover:bg-transparent"
    >
      {label}
    </button>
  );
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
