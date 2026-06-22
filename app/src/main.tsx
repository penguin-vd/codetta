import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App.tsx';
import { DocsPage } from './components/DocsPage.tsx';
import { useRoute } from './router.ts';
import { ThemeProvider } from './ThemeContext.tsx';
import './styles.css';

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
        <ThemeProvider>
            <Root />
        </ThemeProvider>
    </StrictMode>
);
