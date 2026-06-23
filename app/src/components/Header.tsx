import type { ReactNode } from 'react';
import { ThemeToggle } from './ThemeToggle.tsx';

interface Props {
    subtitle: string;
    actions?: ReactNode;
}

export function Header({ subtitle, actions }: Props) {
    return (
        <header className="flex items-center justify-between gap-3 border-b border-line px-4 py-3 sm:px-6">
            <div className="flex min-w-0 items-baseline gap-3">
                <span className="font-serif text-2xl font-semibold text-cream">Codetta</span>
                <span className="hidden font-mono text-[10px] uppercase tracking-[0.25em] text-dim sm:inline">
                    {subtitle}
                </span>
            </div>
            <div className="flex shrink-0 items-center gap-3">
                {actions}
                <ThemeToggle />
            </div>
        </header>
    );
}
