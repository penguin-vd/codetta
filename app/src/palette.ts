// Per-track ink colors, matched to the accent tokens in styles.css.
export const TRACK_COLORS = ["#e0a13c", "#5bb3a6", "#d77a86", "#9a8cd0", "#6fa8d6", "#a8c08a"];

export const trackColor = (i: number) => TRACK_COLORS[i % TRACK_COLORS.length];
