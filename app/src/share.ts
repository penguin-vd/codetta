// Songs travel in the URL hash as base64url-encoded UTF-8 — no dependency, no
// server. The text is tiny (a few hundred bytes), so raw encoding is plenty;
// swap in CompressionStream here if songs ever grow large.

export function encodeSource(source: string): string {
    const bytes = new TextEncoder().encode(source);
    let bin = '';
    for (const b of bytes) bin += String.fromCharCode(b);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function decodeSource(encoded: string): string {
    const b64 = encoded.replace(/-/g, '+').replace(/_/g, '/');
    const bin = atob(b64);
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    return new TextDecoder().decode(bytes);
}

export const sharedHref = (source: string): string => `#/s/${encodeSource(source)}`;

export function shareLink(source: string): string {
    return `${window.location.origin}${window.location.pathname}${sharedHref(source)}`;
}
