import * as Tone from "tone";
import type { Song } from "./types.ts";

export interface Instrument {
  id: string;
  label: string;
  make: () => Tone.PolySynth;
}

export const INSTRUMENTS: Instrument[] = [
  { id: "pulse", label: "Pulse", make: () => new Tone.PolySynth(Tone.Synth, { oscillator: { type: "triangle" }, envelope: { attack: 0.006, decay: 0.2, sustain: 0.5, release: 0.4 } }) },
  { id: "reed", label: "Reed", make: () => new Tone.PolySynth(Tone.Synth, { oscillator: { type: "sawtooth" }, envelope: { attack: 0.02, decay: 0.15, sustain: 0.6, release: 0.3 } }) },
  { id: "chip", label: "Chip", make: () => new Tone.PolySynth(Tone.Synth, { oscillator: { type: "square" }, envelope: { attack: 0.002, decay: 0.1, sustain: 0.35, release: 0.2 } }) },
  { id: "glass", label: "Glass", make: () => new Tone.PolySynth(Tone.FMSynth, { harmonicity: 3, modulationIndex: 2, envelope: { attack: 0.005, decay: 0.3, sustain: 0.2, release: 1.4 } }) },
  { id: "pad", label: "Pad", make: () => new Tone.PolySynth(Tone.AMSynth, { harmonicity: 2, envelope: { attack: 0.4, decay: 0.3, sustain: 0.8, release: 1.6 } }) },
  { id: "pluck", label: "Pluck", make: () => new Tone.PolySynth(Tone.Synth, { oscillator: { type: "triangle" }, envelope: { attack: 0.001, decay: 0.28, sustain: 0, release: 0.3 } }) },
  { id: "sub", label: "Sub", make: () => new Tone.PolySynth(Tone.Synth, { oscillator: { type: "sine" }, envelope: { attack: 0.01, decay: 0.2, sustain: 0.7, release: 0.25 } }) },
];

const BY_ID = new Map(INSTRUMENTS.map((i) => [i.id, i]));

export function defaultInstrument(name: string): string {
  const n = name.toLowerCase();
  if (n.includes("bass") || n.includes("sub")) return "sub";
  if (n.includes("chord") || n.includes("pad")) return "pad";
  if (n.includes("counter") || n.includes("harmony")) return "glass";
  return "pulse";
}

export function songSeconds(song: Song): number {
  const spt = secondsPerTick(song);
  let max = 0;
  for (const track of song.tracks) {
    for (const n of track.notes) max = Math.max(max, (n.ticks + n.durationTicks) * spt);
  }
  return max;
}

export function secondsPerTick(song: Song): number {
  return 60 / song.header.tempo / song.header.ppq;
}

export class Engine {
  private reverb: Tone.Reverb;
  private synths: Tone.PolySynth[] = [];
  private parts: Tone.Part[] = [];
  private endEvent: number | null = null;

  constructor() {
    this.reverb = new Tone.Reverb({ decay: 2.4, wet: 0.18 }).toDestination();
  }

  get seconds(): number {
    return Tone.getTransport().seconds;
  }

  async play(song: Song, instrumentIds: string[], audible: boolean[], onEnd: () => void): Promise<void> {
    await Tone.start();
    this.stop();

    const transport = Tone.getTransport();
    transport.bpm.value = song.header.tempo;
    const spt = secondsPerTick(song);

    song.tracks.forEach((track, i) => {
      const preset = BY_ID.get(instrumentIds[i]) ?? INSTRUMENTS[0];
      const synth = preset.make().connect(this.reverb);
      synth.volume.value = audible[i] ? 0 : -Infinity;
      this.synths.push(synth);

      const events = track.notes.map((n) => ({
        time: n.ticks * spt,
        note: Tone.Frequency(n.midi, "midi").toNote(),
        dur: Math.max(n.durationTicks * spt, 0.03),
        vel: n.velocity,
      }));
      const part = new Tone.Part((time, ev) => {
        synth.triggerAttackRelease(ev.note, ev.dur, time, ev.vel);
      }, events);
      part.start(0);
      this.parts.push(part);
    });

    this.endEvent = transport.scheduleOnce(() => {
      onEnd();
      this.stop();
    }, songSeconds(song) + 0.4);

    transport.position = 0;
    transport.start();
  }

  setAudible(audible: boolean[]): void {
    this.synths.forEach((s, i) => {
      s.volume.value = audible[i] ? 0 : -Infinity;
    });
  }

  stop(): void {
    const transport = Tone.getTransport();
    if (this.endEvent !== null) {
      transport.clear(this.endEvent);
      this.endEvent = null;
    }
    transport.stop();
    transport.cancel();
    this.parts.forEach((p) => p.dispose());
    this.synths.forEach((s) => s.dispose());
    this.parts = [];
    this.synths = [];
  }
}
