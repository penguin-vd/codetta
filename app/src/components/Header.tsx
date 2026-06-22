import type { ReactNode } from 'react';
import { ThemeToggle } from './ThemeToggle.tsx';

interface Props {
    subtitle: string;
    actions?: ReactNode;
}

export function Header({ subtitle, actions }: Props) {
    return (
        <header className="flex items-center justify-between border-b border-line px-6 py-3">
            <div className="flex items-baseline gap-3">
                <span className="font-serif text-2xl font-semibold text-cream">Codetta</span>
                <span className="font-mono text-[10px] uppercase tracking-[0.25em] text-dim">
                    {subtitle}
                </span>
            </div>
            <div className="flex items-center gap-3">
                {actions}
                <ThemeToggle />
            </div>
        </header>
    );
}
