import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App.tsx';
import { DocsPage } from './components/DocsPage.tsx';
import { useRoute } from './router.ts';
import './styles.css';

// App stays mounted under the docs page so editor and audio state survive.
function Root() {
    const route = useRoute();
    return (
        <>
            <App />
            {route.name === 'docs' && <DocsPage slug={route.slug} />}
        </>
    );
}

createRoot(document.getElementById('root')!).render(
    <StrictMode>
        <Root />
    </StrictMode>
);
