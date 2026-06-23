import { useSyncExternalStore } from 'react';

// Phone-sized viewports get a separate, player-first layout (see MobileApp).
const QUERY = '(max-width: 768px)';

const subscribe = (onChange: () => void) => {
    const mql = window.matchMedia(QUERY);
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
};

export function useIsMobile(): boolean {
    return useSyncExternalStore(
        subscribe,
        () => window.matchMedia(QUERY).matches,
        () => false
    );
}
