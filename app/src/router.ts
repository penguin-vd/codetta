import { useSyncExternalStore } from 'react';
import { decodeSource } from './share.ts';

// Hash-based routing — enough for a second page without pulling in a router.
//   #/            the editor app
//   #/docs        the docs index
//   #/docs/<slug> a specific docs entry
//   #/s/<encoded> a shared song (source lives in the URL, never localStorage)

export type Route =
    | { name: 'app' }
    | { name: 'docs'; slug: string | null }
    | { name: 'shared'; source: string };

function parse(hash: string): Route {
    const path = hash.replace(/^#/, '');

    const docs = path.match(/^\/docs(?:\/(.+))?$/);
    if (docs) return { name: 'docs', slug: docs[1] ? decodeURIComponent(docs[1]) : null };

    const shared = path.match(/^\/s\/(.+)$/);
    if (shared) {
        try {
            return { name: 'shared', source: decodeSource(shared[1]) };
        } catch {
            // Corrupt link — fall through to the normal editor.
        }
    }

    return { name: 'app' };
}

const subscribe = (onChange: () => void) => {
    window.addEventListener('hashchange', onChange);
    return () => window.removeEventListener('hashchange', onChange);
};

export function useRoute(): Route {
    const hash = useSyncExternalStore(
        subscribe,
        () => window.location.hash,
        () => ''
    );
    return parse(hash);
}

export const docsHref = (slug?: string): string => (slug ? `#/docs/${slug}` : '#/docs');
