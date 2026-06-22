import { ArrowLeft } from 'lucide-react';
import { useEffect, useRef } from 'react';
import { DOC_KINDS, DOCS, type DocEntry, docBySlug } from '../docs.ts';
import { docsHref } from '../router.ts';
import { Header } from './Header.tsx';

interface Props {
    slug: string | null;
}

export function DocsPage({ slug }: Props) {
    const entry = slug ? docBySlug(slug) : undefined;
    const contentRef = useRef<HTMLDivElement>(null);

    // Esc returns to the editor; jumping between entries scrolls back to the top.
    useEffect(() => {
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') window.location.hash = '#/';
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, []);
    // biome-ignore lint/correctness/useExhaustiveDependencies: scroll to top on slug change is intentional
    useEffect(() => contentRef.current?.scrollTo(0, 0), [slug]);

    return (
        <div className="fixed inset-0 z-50 grid grid-rows-[auto_1fr] bg-bg text-cream">
            <Header
                subtitle="language reference"
                actions={
                    <a
                        href="#/"
                        className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-cream transition hover:border-gold/50 hover:text-gold"
                    >
                        <ArrowLeft size={14} />
                        Editor
                    </a>
                }
            />

            <div className="grid min-h-0 grid-cols-[240px_1fr]">
                <Sidebar activeSlug={entry?.slug ?? null} />
                <div ref={contentRef} className="min-h-0 overflow-auto">
                    {entry ? <Article entry={entry} /> : <Overview />}
                </div>
            </div>
        </div>
    );
}

function Sidebar({ activeSlug }: { activeSlug: string | null }) {
    return (
        <nav className="min-h-0 overflow-auto border-r border-line px-3 py-5">
            <a
                href={docsHref()}
                className={`block rounded px-3 py-1.5 font-mono text-xs ${
                    activeSlug === null ? 'bg-raise text-gold' : 'text-dim hover:text-cream'
                }`}
            >
                Overview
            </a>
            {DOC_KINDS.map((kind) => (
                <div key={kind} className="mt-5">
                    <div className="px-3 pb-1.5 font-mono text-[10px] uppercase tracking-[0.2em] text-dim/70">
                        {kind}s
                    </div>
                    {DOCS.filter((d) => d.kind === kind).map((d) => (
                        <a
                            key={d.slug}
                            href={docsHref(d.slug)}
                            className={`block rounded px-3 py-1.5 font-mono text-xs transition ${
                                d.slug === activeSlug
                                    ? 'bg-raise text-gold'
                                    : 'text-dim hover:text-cream'
                            }`}
                        >
                            {d.title}
                        </a>
                    ))}
                </div>
            ))}
        </nav>
    );
}

function Overview() {
    return (
        <div className="mx-auto max-w-2xl px-10 py-10">
            <h1 className="font-serif text-3xl font-semibold text-cream">Language reference</h1>
            <p className="mt-3 leading-relaxed text-dim">
                Codetta is a small language for writing music as code. Define chords and phrases,
                arrange them into sections and a song, then play or export to MIDI. Pick a topic, or
                hover a keyword in the editor and follow its{' '}
                <span className="text-cream">Open docs</span> link.
            </p>

            <a
                href={`${import.meta.env.BASE_URL}LANGUAGE.md`}
                target="_blank"
                rel="noopener"
                className="mt-5 inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs text-cream transition hover:border-gold/50 hover:text-gold"
            >
                Full reference (LANGUAGE.md)
                <span className="text-[10px]">↗</span>
            </a>

            {DOC_KINDS.map((kind) => (
                <section key={kind} className="mt-9">
                    <h2 className="font-mono text-[11px] uppercase tracking-[0.2em] text-dim">
                        {kind}s
                    </h2>
                    <div className="mt-3 grid gap-2">
                        {DOCS.filter((d) => d.kind === kind).map((d) => (
                            <a
                                key={d.slug}
                                href={docsHref(d.slug)}
                                className="group rounded-lg border border-line bg-panel px-4 py-3 transition hover:border-gold/40"
                            >
                                <div className="font-mono text-sm text-cream group-hover:text-gold">
                                    {d.title}
                                </div>
                                <div className="mt-0.5 text-sm text-dim">{d.summary}</div>
                            </a>
                        ))}
                    </div>
                </section>
            ))}
        </div>
    );
}

function Article({ entry }: { entry: DocEntry }) {
    return (
        <article className="mx-auto max-w-2xl px-10 py-10">
            <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-dim">
                {entry.kind}
            </div>
            <h1 className="mt-1 font-serif text-4xl font-semibold text-cream">{entry.title}</h1>
            <p className="mt-3 text-lg leading-relaxed text-cream/90">{entry.summary}</p>

            <Label>Syntax</Label>
            <Code text={entry.syntax} />

            <Label>Example</Label>
            <Code text={entry.example} />

            <div className="mt-7 space-y-3">
                {entry.body.map((p, i) => (
                    <p key={i} className="leading-relaxed text-dim">
                        {p}
                    </p>
                ))}
            </div>

            {entry.see && entry.see.length > 0 && (
                <div className="mt-8 border-t border-line pt-5">
                    <Label>See also</Label>
                    <div className="mt-1 flex flex-wrap gap-2">
                        {entry.see.map((s) => {
                            const target = docBySlug(s);
                            return (
                                target && (
                                    <a
                                        key={s}
                                        href={docsHref(s)}
                                        className="rounded-md border border-line bg-raise px-2.5 py-1 font-mono text-xs text-dim transition hover:border-gold/50 hover:text-gold"
                                    >
                                        {target.title}
                                    </a>
                                )
                            );
                        })}
                    </div>
                </div>
            )}
        </article>
    );
}

const Label = ({ children }: { children: string }) => (
    <div className="mt-7 font-mono text-[10px] uppercase tracking-[0.2em] text-dim">{children}</div>
);

const Code = ({ text }: { text: string }) => (
    <pre className="mt-2 overflow-x-auto rounded-lg border border-line bg-panel px-4 py-3 font-mono text-[13px] leading-relaxed text-sage">
        {text}
    </pre>
);
