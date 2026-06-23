import { ArrowLeft, Menu } from 'lucide-react';
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
    const navRef = useRef<HTMLDetailsElement>(null);

    // Esc returns to the editor; jumping between entries scrolls back to the top.
    useEffect(() => {
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') window.location.hash = '#/';
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, []);
    // biome-ignore lint/correctness/useExhaustiveDependencies: reset position + close mobile nav on slug change
    useEffect(() => {
        contentRef.current?.scrollTo(0, 0);
        if (navRef.current) navRef.current.open = false;
    }, [slug]);

    return (
        <div className="fixed inset-0 z-50 flex flex-col overflow-hidden bg-bg text-cream">
            <Header
                subtitle="language reference"
                actions={
                    <a
                        href="#/"
                        className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-3 py-2 font-mono text-xs font-semibold uppercase tracking-wider text-cream transition hover:border-gold/50 hover:text-gold sm:px-4"
                    >
                        <ArrowLeft size={14} />
                        Editor
                    </a>
                }
            />

            <div className="flex min-h-0 min-w-0 flex-1 flex-col md:grid md:grid-cols-[240px_minmax(0,1fr)]">
                {/* Mobile: the topic list collapses behind a disclosure. */}
                <details ref={navRef} className="border-b border-line md:hidden">
                    <summary className="flex cursor-pointer items-center gap-2 px-4 py-3 font-mono text-xs uppercase tracking-wider text-dim marker:content-none">
                        <Menu size={15} />
                        Browse topics
                    </summary>
                    <div className="max-h-[55vh] overflow-auto border-t border-line">
                        <Sidebar activeSlug={entry?.slug ?? null} />
                    </div>
                </details>

                {/* Desktop: persistent sidebar. */}
                <div className="hidden min-h-0 overflow-auto border-r border-line md:block">
                    <Sidebar activeSlug={entry?.slug ?? null} />
                </div>

                <div ref={contentRef} className="min-h-0 min-w-0 flex-1 overflow-auto">
                    {entry ? <Article entry={entry} /> : <Overview />}
                </div>
            </div>
        </div>
    );
}

function Sidebar({ activeSlug }: { activeSlug: string | null }) {
    return (
        <nav className="px-3 py-4">
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
        <div className="mx-auto max-w-2xl px-5 py-7 md:px-10 md:py-10">
            <h1 className="font-serif text-2xl font-semibold text-cream md:text-3xl">
                The Codetta Language
            </h1>
            <p className="mt-3 leading-relaxed text-dim">
                Codetta is a small declarative language for writing music as code. You define
                reusable chords and phrases, arrange them into sections of parallel tracks, and lay
                those sections out in a song. The result compiles to timed note events for browser
                playback or MIDI export.
            </p>

            <Section title="Program structure">
                <P>
                    A score is a flat list of declarations — settings, chords, phrases, sections,
                    and a <Link slug="song">song</Link>. Order doesn't matter; all names are
                    collected before references are resolved.
                </P>
                <Pre>{`tempo 120
time_signature 4/4

chord Cmaj = [C4 E4 G4]

phrase melody =
  C4.quarter E4.quarter G4.half

section verse =
  track lead: melody

song =
  verse`}</Pre>
            </Section>

            <Section title="Notes and durations">
                <P>
                    A <Link slug="note">note</Link> is a pitch letter (A–G), an optional accidental
                    (<Kw>#</Kw> or <Kw>b</Kw>), and an octave number — <Kw>C4</Kw> is middle C.
                    Attach a <Link slug="duration">duration</Link> with a dot.
                </P>
                <Pre>{`C4.quarter   F#3.eighth   Bb4.half`}</Pre>
                <P>
                    Durations are fractions of a bar: <Kw>whole</Kw>, <Kw>half</Kw>,{' '}
                    <Kw>quarter</Kw>, <Kw>eighth</Kw>, <Kw>sixteenth</Kw>. Add <Kw>.dot</Kw> to
                    extend by half, or prefix with a number to multiply: <Kw>.2whole</Kw> spans two
                    bars. A <Link slug="rest">rest</Link> is silence for a duration:{' '}
                    <Kw>rest.quarter</Kw>.
                </P>
            </Section>

            <Section title="Chords">
                <P>
                    A <Link slug="chord">chord</Link> names a stack of notes. Reference it by name
                    with a duration to play all notes simultaneously. You can also write inline
                    chords directly with brackets.
                </P>
                <Pre>{`chord Cmaj = [C4 E4 G4]

-- as a reference:
Cmaj.whole

-- or inline (no definition needed):
[C4 E4 G4].whole`}</Pre>
            </Section>

            <Section title="Phrases">
                <P>
                    A <Link slug="phrase">phrase</Link> is a reusable line of music — notes, rests,
                    chords, and dynamics laid out in time. Elements are placed one after another
                    along a running cursor.
                </P>
                <Pre>{`phrase melody =
  C4.quarter E4.quarter G4.quarter rest.quarter
  D4.half C4.half`}</Pre>
                <P>
                    Use a <Link slug="position">voice marker</Link> (<Kw>@bar.beat</Kw>) to reset
                    the cursor and start a second voice for counterpoint.{' '}
                    <Link slug="dynamic">Dynamics</Link> set loudness within a phrase.
                </P>
                <Pre>{`phrase counterpoint =
  E4.whole E4.whole
  @0 C3.whole G3.whole         -- a lower voice

  dynamic @0 p
  dynamic @0.3 crescendo to f over 1 bar`}</Pre>
            </Section>

            <Section title="Sections and tracks">
                <P>
                    A <Link slug="section">section</Link> groups parallel{' '}
                    <Link slug="track">tracks</Link> that play together. Each track is one voice — a
                    phrase reference, chords, notes, or a sequence of them.
                </P>
                <Pre>{`section verse =
  track melody:  melody
  track counter: melody transpose +2 reverse
  track bass:    bassline`}</Pre>
            </Section>

            <Section title="Transforms">
                <P>Transforms modify phrases and chords on a track. Chain them left to right.</P>
                <div className="mt-3 grid grid-cols-[auto_1fr] gap-x-5 gap-y-1.5 rounded-lg border border-line bg-panel px-4 py-3 text-[13px]">
                    <Kw>transpose ±n</Kw>
                    <span className="text-dim">shift pitch by semitones</span>
                    <Kw>reverse</Kw>
                    <span className="text-dim">play backwards</span>
                    <Kw>augment xN</Kw>
                    <span className="text-dim">stretch durations (slower)</span>
                    <Kw>diminish xN</Kw>
                    <span className="text-dim">compress durations (faster)</span>
                    <Kw>arp[.mode] [xN]</Kw>
                    <span className="text-dim">
                        arpeggiate — <Link slug="arp">up</Link>, down, up_down, bounce
                    </span>
                </div>
                <Pre>{`melody transpose +5 augment x2
Cmaj.2whole arp.bounce x2`}</Pre>
            </Section>

            <Section title="Song">
                <P>
                    The <Link slug="song">song</Link> block arranges sections in play order. Repeat
                    with <Kw>* N</Kw>. Without a song block there is nothing to play.
                </P>
                <Pre>{`song =
  intro
  verse * 2
  chorus
  verse
  chorus * 2`}</Pre>
            </Section>

            <div className="mt-10 flex flex-col items-start gap-3 border-t border-line pt-6 sm:flex-row sm:items-center sm:gap-4">
                <a
                    href={`${import.meta.env.BASE_URL}LANGUAGE.md`}
                    target="_blank"
                    rel="noopener"
                    className="inline-flex items-center gap-2 rounded-md border border-line bg-raise px-4 py-2 font-mono text-xs text-cream transition hover:border-gold/50 hover:text-gold"
                >
                    Full reference (LANGUAGE.md)
                    <span className="text-[10px]">↗</span>
                </a>
                <span className="text-sm text-dim">or pick a topic in the sidebar</span>
            </div>
        </div>
    );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
    return (
        <section className="mt-9">
            <h2 className="font-serif text-xl font-semibold text-cream">{title}</h2>
            <div className="mt-3">{children}</div>
        </section>
    );
}

function P({ children }: { children: React.ReactNode }) {
    return <p className="mt-3 leading-relaxed text-dim first:mt-0">{children}</p>;
}

function Kw({ children }: { children: React.ReactNode }) {
    return <code className="font-mono text-sage">{children}</code>;
}

function Link({ slug, children }: { slug: string; children: React.ReactNode }) {
    return (
        <a
            href={docsHref(slug)}
            className="text-cream underline decoration-line underline-offset-2 transition hover:text-gold hover:decoration-gold/50"
        >
            {children}
        </a>
    );
}

function Pre({ children }: { children: string }) {
    return (
        <pre className="mt-3 overflow-x-auto rounded-lg border border-line bg-panel px-4 py-3 font-mono text-[13px] leading-relaxed text-sage">
            {children}
        </pre>
    );
}

function Article({ entry }: { entry: DocEntry }) {
    return (
        <article className="mx-auto max-w-2xl px-5 py-7 md:px-10 md:py-10">
            <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-dim">
                {entry.kind}
            </div>
            <h1 className="mt-1 font-serif text-3xl font-semibold text-cream md:text-4xl">
                {entry.title}
            </h1>
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
