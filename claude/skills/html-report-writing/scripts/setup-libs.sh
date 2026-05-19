#!/usr/bin/env bash
# Download KaTeX + Prism into a local lib/ directory for air-gap / offline distribution.
#
# Usage:
#   bash setup-libs.sh [TARGET_DIR]
#
# Example:
#   bash claude/skills/html-report-writing/scripts/setup-libs.sh docs/assets/lib
#
# After running, rewrite the CDN urls in your generated HTML to local paths.
# See reference/math-and-code.md for the sed snippet.

set -euo pipefail

TARGET="${1:-docs/assets/lib}"
KATEX_VER="0.16.11"
PRISM_VER="1.29.0"

# Curated minimum: enough for typical technical reports.
# Add more by editing the array below.
PRISM_LANGS=(
  markup css clike javascript bash python json yaml typescript rust go
)

KATEX_FONTS=(
  KaTeX_AMS-Regular
  KaTeX_Caligraphic-Bold KaTeX_Caligraphic-Regular
  KaTeX_Fraktur-Bold KaTeX_Fraktur-Regular
  KaTeX_Main-Bold KaTeX_Main-BoldItalic KaTeX_Main-Italic KaTeX_Main-Regular
  KaTeX_Math-BoldItalic KaTeX_Math-Italic
  KaTeX_SansSerif-Bold KaTeX_SansSerif-Italic KaTeX_SansSerif-Regular
  KaTeX_Script-Regular
  KaTeX_Size1-Regular KaTeX_Size2-Regular KaTeX_Size3-Regular KaTeX_Size4-Regular
  KaTeX_Typewriter-Regular
)

CDN="https://cdn.jsdelivr.net/npm"

mkdir -p "$TARGET/fonts"

echo "Installing KaTeX ${KATEX_VER} into ${TARGET}/"
curl -fLsS -o "$TARGET/katex.min.css"      "${CDN}/katex@${KATEX_VER}/dist/katex.min.css"
curl -fLsS -o "$TARGET/katex.min.js"       "${CDN}/katex@${KATEX_VER}/dist/katex.min.js"
curl -fLsS -o "$TARGET/auto-render.min.js" "${CDN}/katex@${KATEX_VER}/dist/contrib/auto-render.min.js"

# KaTeX CSS references woff2 fonts under ./fonts/ — keep that layout.
for font in "${KATEX_FONTS[@]}"; do
  curl -fLsS -o "$TARGET/fonts/${font}.woff2" \
    "${CDN}/katex@${KATEX_VER}/dist/fonts/${font}.woff2"
done

echo "Installing Prism ${PRISM_VER} into ${TARGET}/"
curl -fLsS -o "$TARGET/prism.min.css" \
  "${CDN}/prismjs@${PRISM_VER}/themes/prism-tomorrow.min.css"
curl -fLsS -o "$TARGET/prism.min.js" \
  "${CDN}/prismjs@${PRISM_VER}/components/prism-core.min.js"

for lang in "${PRISM_LANGS[@]}"; do
  curl -fLsS -o "$TARGET/prism-${lang}.min.js" \
    "${CDN}/prismjs@${PRISM_VER}/components/prism-${lang}.min.js"
done

echo
echo "Done. Files in ${TARGET}/:"
ls -1 "$TARGET" | sed 's/^/  /'
echo
echo "Next: rewrite CDN urls in your HTML to local paths."
echo "See reference/math-and-code.md (sed snippet)."
