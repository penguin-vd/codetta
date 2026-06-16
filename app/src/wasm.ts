import type { Song } from "./types.ts";

interface CodettaExports {
  memory: WebAssembly.Memory;
  alloc(len: number): number;
  compileJson(ptr: number, len: number): number;
  compileMidi(ptr: number, len: number): number;
  diagnose(ptr: number, len: number): number;
  resultPtr(): number;
  resultLen(): number;
}

export class CompileError extends Error {}

let exportsPromise: Promise<CodettaExports> | null = null;

function load(): Promise<CodettaExports> {
  if (!exportsPromise) {
    exportsPromise = (async () => {
      const res = await fetch(`${import.meta.env.BASE_URL}codetta.wasm`);
      const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(), {});
      return instance.exports as unknown as CodettaExports;
    })();
  }
  return exportsPromise;
}

async function run(name: "compileJson" | "compileMidi" | "diagnose", source: string): Promise<Uint8Array> {
  const ex = await load();
  const bytes = new TextEncoder().encode(source);
  const ptr = ex.alloc(bytes.length);
  new Uint8Array(ex.memory.buffer, ptr, bytes.length).set(bytes);

  const ok = ex[name](ptr, bytes.length);
  const out = new Uint8Array(ex.memory.buffer, ex.resultPtr(), ex.resultLen()).slice();
  if (!ok) throw new CompileError(new TextDecoder().decode(out));
  return out;
}

export async function compileSong(source: string): Promise<Song> {
  return JSON.parse(new TextDecoder().decode(await run("compileJson", source))) as Song;
}

export function compileMidi(source: string): Promise<Uint8Array> {
  return run("compileMidi", source);
}

export interface Diag {
  severity: "error" | "warning";
  line: number;
  column: number;
  message: string;
}

// Every diagnostic for the source: syntax errors, missing-setting warnings,
// and undefined references, each with a 1-based line/column.
export async function diagnose(source: string): Promise<Diag[]> {
  const bytes = await run("diagnose", source);
  return JSON.parse(new TextDecoder().decode(bytes)) as Diag[];
}

export const preloadWasm = (): Promise<unknown> => load();
