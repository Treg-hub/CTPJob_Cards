#!/usr/bin/env bash
# Regenerates docs/*.html from docs/*.md using pandoc.
#
# Markdown is the single source of truth for CTP Job Cards documentation.
# docs/index.html is handwritten and never overwritten by this script.
#
# Usage:
#   tools/build-docs.sh            # regenerate HTML only
#   tools/build-docs.sh --pdf      # also regenerate PDFs (needs a PDF engine)
#   tools/build-docs.sh --check    # CI mode: fail if committed HTML drifts from .md
#
# The PowerShell sibling tools/build-docs.ps1 is the canonical local Windows
# entry point; this script is here so CI (and any *nix dev) can do the same.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"

if ! command -v pandoc >/dev/null 2>&1; then
  echo "pandoc not found on PATH." >&2
  echo "Install via: apt-get install pandoc / brew install pandoc" >&2
  exit 1
fi

if [ ! -d "$DOCS_DIR" ]; then
  echo "docs/ directory not found at $DOCS_DIR" >&2
  exit 1
fi

MODE="build"
PDF=0
for arg in "$@"; do
  case "$arg" in
    --pdf)   PDF=1 ;;
    --check) MODE="check" ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

OUT_DIR="$DOCS_DIR"
if [ "$MODE" = "check" ]; then
  OUT_DIR="$(mktemp -d -t ctp-docs-build-XXXXXX)"
  trap 'rm -rf "$OUT_DIR"' EXIT
  # Copy the stylesheet so the relative CSS reference resolves and the
  # generated HTML is byte-identical to what `tools/build-docs.sh` produces
  # in-tree. Without this the --check diff would always be dirty.
  cp "$DOCS_DIR/docs.css" "$OUT_DIR/docs.css"
fi

# Always use the relative reference so committed and check-mode HTML match
# byte-for-byte. The stylesheet is sibling to every generated file.
CSS_REF="docs.css"

shopt -s nullglob
MD_FILES=("$DOCS_DIR"/*.md)
if [ ${#MD_FILES[@]} -eq 0 ]; then
  echo "No markdown files found in $DOCS_DIR"
  exit 0
fi

FAILED=0
for md in "${MD_FILES[@]}"; do
  name="$(basename "${md%.md}")"
  html_out="$OUT_DIR/$name.html"
  title="$(echo "$name" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2)}1')"
  echo "→ $name.md → $name.html"

  if ! pandoc \
      --from=gfm \
      --to=html5 \
      --standalone \
      --metadata="title=$title" \
      --css="$CSS_REF" \
      --output="$html_out" \
      "$md"; then
    echo "  pandoc failed for $name.md" >&2
    FAILED=$((FAILED+1))
  fi

  if [ "$PDF" = "1" ] && [ "$MODE" != "check" ]; then
    pdf_out="$OUT_DIR/$name.pdf"
    echo "  + $name.pdf"
    pandoc --from=gfm --output="$pdf_out" "$md" || \
      echo "  pandoc PDF failed for $name.md — install a PDF engine (wkhtmltopdf or LaTeX)." >&2
  fi
done

if [ "$MODE" = "check" ]; then
  echo
  echo "Diffing temp build against committed HTML..."
  DRIFT=0
  for md in "${MD_FILES[@]}"; do
    name="$(basename "${md%.md}")"
    if [ ! -f "$DOCS_DIR/$name.html" ]; then
      echo "  MISSING: $name.html is not committed" >&2
      DRIFT=$((DRIFT+1))
      continue
    fi
    if ! diff -q "$OUT_DIR/$name.html" "$DOCS_DIR/$name.html" >/dev/null; then
      echo "  DRIFT:   $name.html differs from regenerated output" >&2
      DRIFT=$((DRIFT+1))
    fi
  done

  if [ "$DRIFT" -gt 0 ]; then
    echo
    echo "$DRIFT file(s) out of sync. Run 'tools/build-docs.sh' locally and commit the result." >&2
    exit 1
  fi
  echo "All HTML matches markdown source."
fi

if [ "$FAILED" -gt 0 ]; then exit 1; fi
