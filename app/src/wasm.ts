import type { Song } from './types.ts';

interface CodettaExports {
    memory: WebAssembly.Memory;
    alloc(len: number): number;
    compileJson(ptr: number, len: number): number;
    compileMidi(ptr: number, len: number): number;
    diagnose(ptr: number, len: number): number;
    completions(ptr: number, len: number): number;
    hover(ptr: number, len: number, line: number, column: number): number;
    definition(ptr: number, len: number, line: number, column: number): number;
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

// Copies `source` into WASM memory, runs `invoke`, and copies the result back
// out before the next call can overwrite it. A falsy return means the result
// holds an error message rather than output.
async function call(
    source: string,
    invoke: (ex: CodettaExports, ptr: number, len: number) => number
): Promise<Uint8Array> {
    const ex = await load();
    const bytes = new TextEncoder().encode(source);
    const ptr = ex.alloc(bytes.length);
    new Uint8Array(ex.memory.buffer, ptr, bytes.length).set(bytes);

    const ok = invoke(ex, ptr, bytes.length);
    const out = new Uint8Array(ex.memory.buffer, ex.resultPtr(), ex.resultLen()).slice();
    if (!ok) throw new CompileError(new TextDecoder().decode(out));
    return out;
}

const run = (
    name: 'compileJson' | 'compileMidi' | 'diagnose',
    source: string
): Promise<Uint8Array> => call(source, (ex, ptr, len) => ex[name](ptr, len));

export async function compileSong(source: string): Promise<Song> {
    return JSON.parse(new TextDecoder().decode(await run('compileJson', source))) as Song;
}

export function compileMidi(source: string): Promise<Uint8Array> {
    return run('compileMidi', source);
}

export interface Diag {
    severity: 'error' | 'warning';
    line: number;
    column: number;
    message: string;
}

// Every diagnostic for the source: syntax errors, missing-setting warnings,
// and undefined references, each with a 1-based line/column.
export async function diagnose(source: string): Promise<Diag[]> {
    const bytes = await run('diagnose', source);
    return JSON.parse(new TextDecoder().decode(bytes)) as Diag[];
}

export interface Completion {
    label: string;
    detail: string;
    type: string; // CodeMirror's Completion.type
}

export async function completions(source: string): Promise<Completion[]> {
    const bytes = await call(source, (ex, ptr, len) => ex.completions(ptr, len));
    return JSON.parse(new TextDecoder().decode(bytes)) as Completion[];
}

export interface Hover {
    title: string;
    detail: string;
}

export async function hover(source: string, line: number, column: number): Promise<Hover | null> {
    const bytes = await call(source, (ex, ptr, len) => ex.hover(ptr, len, line, column));
    if (bytes.length === 0) return null;
    return JSON.parse(new TextDecoder().decode(bytes)) as Hover;
}

export interface Definition {
    line: number;
    column: number;
}

export async function definition(
    source: string,
    line: number,
    column: number
): Promise<Definition | null> {
    const bytes = await call(source, (ex, ptr, len) => ex.definition(ptr, len, line, column));
    if (bytes.length === 0) return null;
    return JSON.parse(new TextDecoder().decode(bytes)) as Definition;
}

export const preloadWasm = (): Promise<unknown> => load();
