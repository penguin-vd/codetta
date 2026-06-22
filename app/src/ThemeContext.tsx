import { createContext, type ReactNode, useContext, useEffect, useState } from 'react';

type Theme = 'dark' | 'light';

interface ThemeContextValue {
    dark: boolean;
    theme: Theme;
    toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

function getInitialTheme(): Theme {
    const stored = localStorage.getItem('codetta-theme');
    if (stored === 'light') return 'light';
    return 'dark';
}

export function ThemeProvider({ children }: { children: ReactNode }) {
    const [theme, setTheme] = useState<Theme>(getInitialTheme);
    const dark = theme === 'dark';

    useEffect(() => {
        document.documentElement.classList.toggle('light', !dark);
        localStorage.setItem('codetta-theme', theme);
    }, [theme, dark]);

    const toggleTheme = () => setTheme((t) => (t === 'dark' ? 'light' : 'dark'));

    return <ThemeContext value={{ dark, theme, toggleTheme }}>{children}</ThemeContext>;
}

export function useTheme(): ThemeContextValue {
    const ctx = useContext(ThemeContext);
    if (!ctx) throw new Error('useTheme must be used within a ThemeProvider');
    return ctx;
}
