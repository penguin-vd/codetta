import {
    acceptCompletion,
    autocompletion,
    type CompletionContext,
    type CompletionResult,
} from '@codemirror/autocomplete';
import { indentLess, insertTab } from '@codemirror/commands';
import { type Diagnostic, linter, lintGutter } from '@codemirror/lint';
import { EditorView, hoverTooltip, keymap } from '@codemirror/view';
import CodeMirror from '@uiw/react-codemirror';
import { useMemo } from 'react';
import { codaLanguage, createEditorTheme } from '../coda-language.ts';
import { docFor } from '../docs.ts';
import { docsHref } from '../router.ts';
import { useTheme } from '../ThemeContext.tsx';
import { completions, definition, diagnose, hover } from '../wasm.ts';

const codaLinter = linter(
    async (view): Promise<Diagnostic[]> => {
        const doc = view.state.doc;
        const diags = await diagnose(doc.toString());
        return diags.map((d) => {
            const line = doc.line(Math.min(Math.max(d.line, 1), doc.lines));
            const from = Math.min(line.from + Math.max(d.column, 1) - 1, line.to);
            const to = from < line.to ? line.to : Math.min(from + 1, doc.length);
            return { from, to, severity: d.severity, message: d.message };
        });
    },
    { delay: 150 }
);

// `validFor` lets CodeMirror filter the full set as the word grows, so we only
// cross the WASM boundary once per word rather than on every keystroke.
async function codaCompletions(context: CompletionContext): Promise<CompletionResult | null> {
    // No completions inside comments
    const line = context.state.doc.lineAt(context.pos);
    const textBefore = line.text.slice(0, context.pos - line.from);
    if (textBefore.includes('--')) return null;

    // After `arp.` — offer arp mode completions only
    const dotWord = context.matchBefore(/arp\.(\w*)$/);
    if (dotWord) {
        const items = await completions(context.state.doc.toString());
        const modes = items.filter(
            (c) => c.type === 'property' && ['up', 'down', 'up_down', 'bounce'].includes(c.label)
        );
        return {
            from: dotWord.from + 4, // after "arp."
            validFor: /^\w*$/,
            options: modes.map((c) => ({ label: c.label, detail: c.detail, type: c.type })),
        };
    }

    const word = context.matchBefore(/\w+/);
    if (!word || (word.from === word.to && !context.explicit)) return null;

    const items = await completions(context.state.doc.toString());
    return {
        from: word.from,
        validFor: /^\w*$/,
        options: items.map((c) => ({ label: c.label, detail: c.detail, type: c.type })),
    };
}

const codaHover = hoverTooltip(async (view, pos) => {
    const doc = view.state.doc;
    const line = doc.lineAt(pos);
    const src = doc.toString();
    const [info, def] = await Promise.all([
        hover(src, line.number, pos - line.from + 1),
        definition(src, line.number, pos - line.from + 1),
    ]);
    if (!info) return null;

    // User references jump to their definition; everything else falls back to docs.
    const range = view.state.wordAt(pos);
    const word = range ? view.state.sliceDoc(range.from, range.to) : '';
    const charBefore =
        range && range.from > 0 ? view.state.sliceDoc(range.from - 1, range.from) : '';
    const slug = def ? null : charBefore === '@' ? 'position' : docFor(word, info.title);
    const target = def ? doc.line(def.line).from + def.column - 1 : null;

    return {
        pos,
        create() {
            const dom = document.createElement('div');
            dom.className = 'cm-coda-hover';
            const title = dom.appendChild(document.createElement('div'));
            title.className = 'cm-coda-hover-title';
            title.textContent = info.title;
            if (info.detail) {
                const detail = dom.appendChild(document.createElement('div'));
                detail.className = 'cm-coda-hover-detail';
                detail.textContent = info.detail;
            }
            const link = dom.appendChild(document.createElement('a'));
            link.className = 'cm-coda-hover-link';
            if (target != null) {
                link.textContent = 'Go to definition →';
                link.href = '#';
                link.onclick = (e) => {
                    e.preventDefault();
                    view.dispatch({ selection: { anchor: target }, scrollIntoView: true });
                    view.focus();
                };
            } else if (slug) {
                link.textContent = 'Open docs →';
                link.href = docsHref(slug);
            } else {
                dom.removeChild(link);
            }
            return { dom };
        },
    };
});

// Jump to the symbol's definition, or open its docs when it has none.
async function goToSymbol(view: EditorView, pos: number) {
    const doc = view.state.doc;
    const line = doc.lineAt(pos);
    const def = await definition(doc.toString(), line.number, pos - line.from + 1);
    if (def) {
        const target = doc.line(def.line).from + def.column - 1;
        view.dispatch({ selection: { anchor: target }, scrollIntoView: true });
        view.focus();
        return;
    }
    const range = view.state.wordAt(pos);
    const before =
        range && range.from > 0
            ? doc.sliceString(range.from - 1, range.from)
            : doc.sliceString(pos, pos + 1);
    if (before === '@') {
        window.location.hash = docsHref('position');
        return;
    }
    const slug = docFor(range ? view.state.sliceDoc(range.from, range.to) : '');
    if (slug) window.location.hash = docsHref(slug);
}

// Ctrl/Cmd-click or middle-click on a symbol acts as go-to-definition.
const gotoClick = EditorView.domEventHandlers({
    mousedown(event, view) {
        const modClick = event.button === 0 && (event.metaKey || event.ctrlKey);
        const middleClick = event.button === 1;
        if (!modClick && !middleClick) return false;

        const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
        if (pos == null) return false;

        event.preventDefault();
        void goToSymbol(view, pos);
        return true;
    },
});

interface Props {
    value: string;
    onChange: (value: string) => void;
}

export function Editor({ value, onChange }: Props) {
    const { dark } = useTheme();
    const theme = useMemo(() => createEditorTheme(dark), [dark]);

    const extensions = useMemo(
        () => [
            codaLanguage(),
            EditorView.lineWrapping,
            lintGutter(),
            codaLinter,
            codaHover,
            gotoClick,
            autocompletion({ override: [codaCompletions], icons: false }),
            // Tab accepts an open completion, otherwise indents (Shift-Tab dedents).
            keymap.of([
                { key: 'Tab', run: (v) => acceptCompletion(v) || insertTab(v), shift: indentLess },
            ]),
        ],
        []
    );

    return (
        <CodeMirror
            value={value}
            onChange={onChange}
            theme={theme}
            extensions={extensions}
            basicSetup={{
                highlightActiveLine: true,
                highlightActiveLineGutter: true,
                foldGutter: false,
                autocompletion: false,
                bracketMatching: true,
                indentOnInput: false,
            }}
            // Off so our own Tab binding (accept completion, else indent) wins.
            indentWithTab={false}
            height="100%"
            style={{ height: '100%' }}
        />
    );
}
