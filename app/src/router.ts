import { useSyncExternalStore } from 'react';

// Hash-based routing — enough for a second page without pulling in a router.
//   #/            the editor app
//   #/docs        the docs index
//   #/docs/<slug> a specific docs entry

export type Route = { name: 'app' } | { name: 'docs'; slug: string | null };

function parse(hash: string): Route {
    const path = hash.replace(/^#/, '');
    const match = path.match(/^\/docs(?:\/(.+))?$/);
    if (match) return { name: 'docs', slug: match[1] ? decodeURIComponent(match[1]) : null };
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
