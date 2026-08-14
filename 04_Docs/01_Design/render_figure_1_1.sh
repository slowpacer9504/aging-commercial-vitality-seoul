#!/usr/bin/env bash
# Render Figure 1.1 (English research framework) from the standalone Mermaid source file.
#
# Source of truth : figure_1_1_research_framework_en.mmd
# Config          : mermaid_config.json  (wrappingWidth, theme, spacing)
# Outputs         : figure_1_1_research_framework_en.svg  (vector)
#                   figure_1_1_research_framework_en.png  (high-resolution, white bg)
#
# Usage:
#   bash 04_Docs/01_Design/render_figure_1_1.sh           # render both
#   bash 04_Docs/01_Design/render_figure_1_1.sh --png     # PNG only
#   bash 04_Docs/01_Design/render_figure_1_1.sh --svg     # SVG only
#
# Requires Node.js + npx (mermaid-cli is auto-installed on first run via npx).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$SCRIPT_DIR/mermaid_config.json"
OUT_BASE="$SCRIPT_DIR/figure_1_1_research_framework_en"
SCALE=4          # PNG scale factor; viewBox ~1573 wide -> PNG ~3136 px wide
BG="white"

MODE="both"
case "${1:-}" in
  --png) MODE="png" ;;
  --svg) MODE="svg" ;;
  --both|"") MODE="both" ;;
  *) echo "Unknown option: $1" >&2; exit 1 ;;
esac

# --- checks -----------------------------------------------------------------
MMD="$SCRIPT_DIR/figure_1_1_research_framework_en.mmd"
[ -f "$CFG" ] || { echo "Config not found: $CFG" >&2; exit 1; }
[ -f "$MMD" ] || { echo "Mermaid source not found: $MMD" >&2; exit 1; }
echo "Using mermaid source: $MMD"

# --- render -----------------------------------------------------------------
MMDC="npx --yes @mermaid-js/mermaid-cli"

if [ "$MODE" = "svg" ] || [ "$MODE" = "both" ]; then
  echo "Rendering SVG ..."
  $MMDC -i "$MMD" -o "$OUT_BASE.svg" -c "$CFG" -b "$BG"
fi

if [ "$MODE" = "png" ] || [ "$MODE" = "both" ]; then
  echo "Rendering PNG (scale $SCALE) ..."
  $MMDC -i "$MMD" -o "$OUT_BASE.png" -c "$CFG" -b "$BG" -s "$SCALE"
fi

# --- report -----------------------------------------------------------------
echo
echo "Rendered:"
[ -f "$OUT_BASE.svg" ] && echo "  $OUT_BASE.svg"
[ -f "$OUT_BASE.png" ] && echo "  $OUT_BASE.png"
file "$OUT_BASE.svg" "$OUT_BASE.png" 2>/dev/null || true