import { StreamLanguage, HighlightStyle, syntaxHighlighting, LanguageSupport } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import { EditorView } from "@codemirror/view";

const STRUCTURE = new Set(["tempo", "time_signature", "chord", "phrase", "section", "song", "track"]);
const FLOW = new Set([
  "dynamic", "crescendo", "decrescendo", "transpose", "reverse", "augment",
  "diminish", "rest", "to", "over", "bar", "bars", "arp",
]);
const DURATIONS = new Set([
  "whole", "half", "quarter", "eighth", "sixteenth", "thirtysecond", "dotted",
]);
const ARP_MODES = new Set(["up", "down", "up_down", "bounce"]);
const DYNAMICS = new Set(["ppp", "pp", "p", "mp", "mf", "f", "ff", "fff"]);

const coda = StreamLanguage.define({
  name: "coda",
  token(stream) {
    if (stream.eatSpace()) return null;

    if (stream.match(/^--.*$/)) return "lineComment";

    if (stream.match(/^@\d+(\.\d+)?/)) return "meta";
    if (stream.match(/^x\d+/)) return "number";
    if (stream.match(/^[A-G][#b]?\d+/)) return "atom";

    if (stream.match(/^\.\d*[a-z_]+/)) {
      const raw = stream.current().slice(1);
      const word = raw.replace(/^\d+/, "");
      if (DURATIONS.has(word)) return "typeName";
      if (ARP_MODES.has(word)) return "controlKeyword";
      return "propertyName";
    }

    if (stream.match(/^[+-]?\d+(\.\d+)?/)) return "number";

    if (stream.match(/^[A-Za-z_][A-Za-z0-9_]*/)) {
      const text = stream.current();
      if (STRUCTURE.has(text)) return "keyword";
      if (FLOW.has(text)) return "controlKeyword";
      if (DYNAMICS.has(text)) return "string";
      return "variableName";
    }

    if (stream.match(/^[=*/]/)) return "operator";
    stream.next();
    return null;
  },
});

const highlight = HighlightStyle.define([
  { tag: t.keyword, color: "var(--color-gold)", fontWeight: "600" },
  { tag: t.controlKeyword, color: "var(--color-coral)" },
  { tag: t.atom, color: "var(--color-azure)" },
  { tag: t.typeName, color: "var(--color-mint)" },
  { tag: t.propertyName, color: "var(--color-dim)", fontStyle: "italic" },
  { tag: t.number, color: "var(--color-sage)" },
  { tag: t.string, color: "var(--color-iris)", fontWeight: "500" },
  { tag: t.meta, color: "var(--color-gold)", fontStyle: "italic" },
  { tag: t.operator, color: "var(--color-dim)" },
  { tag: t.variableName, color: "var(--color-cream)" },
  { tag: t.lineComment, color: "var(--color-dim)", fontStyle: "italic" },
]);

export const editorTheme = EditorView.theme(
  {
    "&": { backgroundColor: "transparent", color: "var(--color-cream)", height: "100%" },
    ".cm-content": {
      fontFamily: "var(--font-mono)",
      fontSize: "13px",
      lineHeight: "1.7",
      padding: "16px 0 40vh",
      caretColor: "var(--color-gold)",
    },
    ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--color-gold)" },
    "&.cm-focused": { outline: "none" },
    ".cm-gutters": {
      backgroundColor: "transparent",
      color: "color-mix(in srgb, var(--color-dim) 45%, transparent)",
      border: "none",
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
    },
    ".cm-lineNumbers .cm-gutterElement": { padding: "0 3px 0 8px" },
    ".cm-gutter-lint": { width: "13px" },
    ".cm-lint-marker": { width: "8px", height: "8px" },
    ".cm-activeLine": { backgroundColor: "color-mix(in srgb, var(--color-gold) 5%, transparent)" },
    ".cm-activeLineGutter": { backgroundColor: "transparent", color: "var(--color-gold)" },
    ".cm-selectionBackground, &.cm-focused .cm-selectionBackground, ::selection": {
      backgroundColor: "color-mix(in srgb, var(--color-gold) 20%, transparent) !important",
    },
    ".cm-line": { padding: "0 14px" },
    ".cm-lintRange-error": {
      backgroundImage: "none",
      textDecoration: "underline wavy var(--color-coral)",
      textUnderlineOffset: "3px",
    },
    ".cm-lintRange-warning": {
      backgroundImage: "none",
      textDecoration: "underline wavy var(--color-gold)",
      textUnderlineOffset: "3px",
    },
    ".cm-diagnostic-warning": { borderLeftColor: "var(--color-gold)" },
    ".cm-tooltip": {
      backgroundColor: "var(--color-raise)",
      border: "1px solid var(--color-line)",
      borderRadius: "7px",
      color: "var(--color-cream)",
      fontFamily: "var(--font-sans)",
      fontSize: "12px",
    },
    ".cm-diagnostic": { padding: "5px 9px" },
    ".cm-diagnostic-error": { borderLeftColor: "var(--color-coral)" },
    ".cm-tooltip-autocomplete > ul": {
      fontFamily: "var(--font-mono)",
      fontSize: "12px",
      maxHeight: "16em",
    },
    ".cm-tooltip-autocomplete > ul > li": { padding: "3px 9px" },
    ".cm-tooltip-autocomplete > ul > li[aria-selected]": {
      backgroundColor: "color-mix(in srgb, var(--color-gold) 18%, transparent)",
      color: "var(--color-cream)",
    },
    ".cm-completionDetail": {
      color: "var(--color-dim)",
      fontStyle: "italic",
      marginLeft: "1.5em",
    },
    ".cm-coda-hover": { padding: "6px 9px", fontFamily: "var(--font-mono)", fontSize: "12px" },
    ".cm-coda-hover-title": { fontWeight: "600", color: "var(--color-gold)" },
    ".cm-coda-hover-detail": { color: "var(--color-cream)", marginTop: "3px" },
    ".cm-coda-hover-link": {
      display: "inline-block",
      marginTop: "6px",
      color: "var(--color-azure)",
      textDecoration: "none",
      cursor: "pointer",
    },
    ".cm-coda-hover-link:hover": { textDecoration: "underline" },
  },
  { dark: true },
);

export function codaLanguage(): LanguageSupport {
  return new LanguageSupport(coda, [syntaxHighlighting(highlight)]);
}
