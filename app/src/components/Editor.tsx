import { useMemo } from "react";
import CodeMirror from "@uiw/react-codemirror";
import { EditorView, hoverTooltip } from "@codemirror/view";
import { autocompletion, type CompletionContext, type CompletionResult } from "@codemirror/autocomplete";
import { linter, lintGutter, type Diagnostic } from "@codemirror/lint";
import { codaLanguage, editorTheme } from "../coda-language.ts";
import { completions, diagnose, hover } from "../wasm.ts";

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
  { delay: 150 },
);

// `validFor` lets CodeMirror filter the full set as the word grows, so we only
// cross the WASM boundary once per word rather than on every keystroke.
async function codaCompletions(context: CompletionContext): Promise<CompletionResult | null> {
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
  const info = await hover(doc.toString(), line.number, pos - line.from + 1);
  if (!info) return null;

  return {
    pos,
    create() {
      const dom = document.createElement("div");
      dom.className = "cm-coda-hover";
      const title = dom.appendChild(document.createElement("div"));
      title.className = "cm-coda-hover-title";
      title.textContent = info.title;
      if (info.detail) {
        const detail = dom.appendChild(document.createElement("div"));
        detail.className = "cm-coda-hover-detail";
        detail.textContent = info.detail;
      }
      return { dom };
    },
  };
});

interface Props {
  value: string;
  onChange: (value: string) => void;
}

export function Editor({ value, onChange }: Props) {
  const extensions = useMemo(
    () => [
      codaLanguage(),
      EditorView.lineWrapping,
      lintGutter(),
      codaLinter,
      codaHover,
      autocompletion({ override: [codaCompletions], icons: false }),
    ],
    [],
  );

  return (
    <CodeMirror
      value={value}
      onChange={onChange}
      theme={editorTheme}
      extensions={extensions}
      basicSetup={{
        highlightActiveLine: true,
        highlightActiveLineGutter: true,
        foldGutter: false,
        autocompletion: false,
        bracketMatching: true,
        indentOnInput: false,
      }}
      height="100%"
      style={{ height: "100%" }}
    />
  );
}
