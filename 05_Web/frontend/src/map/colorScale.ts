// Diverging color scale anchored at 0. Uses manifest-supplied breaks
// (symmetric around zero) and d3-scale-chromatic's RdYlBu palette
// so NEGATIVE == deep blue (Coldspot) and POSITIVE == deep red (Hotspot) —
// the conventional spatial-statistics reading for signed vitality effects.
//
// 9 colours, 9 breaks. Bucket index `i` covers:
//   i = 0           -> estimate <= breaks[0]            (deepest blue, cold)
//   i in 1..8       -> breaks[i-1] < estimate <= breaks[i] (colours 1..8)
//                     center bucket (i = 4) is around breaks[4] == 0 (neutral)
//   i = 8 (out)     -> estimate > breaks[8]            (clamp: deepest red, hot)

export const COLOR_SCALE_COLORS = [
  "#313695", // very negative (Coldspot)
  "#4575b4",
  "#74add1",
  "#abd9e9", // mildly negative
  "#ffffff", // neutral zero
  "#fdae61", // mildly positive
  "#f46d43",
  "#d73027",
  "#a50026", // very positive (Hotspot)
] as const;

export interface ColorScale {
  breaks: number[];
  colorFor: (estimate: number | null) => string;
}

export function makeColorScale(breaks: number[]): ColorScale {
  if (breaks.length !== COLOR_SCALE_COLORS.length) {
    throw new Error(
      `colorScale: breaks must have exactly ${COLOR_SCALE_COLORS.length} entries; got ${breaks.length}`,
    );
  }
  const mid = Math.floor(breaks.length / 2);
  if (breaks[mid] !== 0) {
    throw new Error("colorScale: centre break must be 0 (diverging symmetric scale)");
  }
  return { breaks, colorFor: estimate => colorFor(estimate, breaks) };
}

export function colorFor(estimate: number | null, breaks: number[]): string {
  if (estimate === null || Number.isNaN(estimate)) return "#cccccc";
  // Step function: first break for which estimate <= break's threshold.
  // Out-of-range values clamp to extremes.
  if (estimate <= breaks[0]!) return COLOR_SCALE_COLORS[0]!;
  if (estimate > breaks[breaks.length - 1]!) return COLOR_SCALE_COLORS[breaks.length - 1]!;
  for (let i = 1; i < breaks.length; i += 1) {
    if (estimate <= breaks[i]!) return COLOR_SCALE_COLORS[i]!;
  }
  // Defensive: should be unreachable given the above checks.
  return COLOR_SCALE_COLORS[breaks.length - 1]!;
}
