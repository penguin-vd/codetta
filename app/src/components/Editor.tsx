import { useMemo } from "react";
import CodeMirror from "@uiw/react-codemirror";
import { EditorView } from "@codemirror/view";
import { linter, lintGutter, type Diagnostic } from "@codemirror/lint";
import { codaLanguage, editorTheme } from "../coda-language.ts";
import { diagnose } from "../wasm.ts";

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

interface Props {
  value: string;
  onChange: (value: string) => void;
}

export function Editor({ value, onChange }: Props) {
  const extensions = useMemo(
    () => [codaLanguage(), EditorView.lineWrapping, lintGutter(), codaLinter],
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
