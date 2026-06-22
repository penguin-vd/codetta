import { Moon, Sun } from 'lucide-react';
import { useTheme } from '../ThemeContext.tsx';

export function ThemeToggle() {
    const { dark, toggleTheme } = useTheme();

    return (
        <button
            type="button"
            onClick={toggleTheme}
            className="grid h-9 w-9 place-items-center rounded-md border border-line bg-raise text-dim transition hover:border-gold/50 hover:text-gold"
            title={dark ? 'Switch to light mode' : 'Switch to dark mode'}
        >
            {dark ? <Sun size={16} /> : <Moon size={16} />}
        </button>
    );
}
