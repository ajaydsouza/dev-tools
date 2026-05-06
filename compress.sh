#!/usr/bin/env bash
# compress.sh — Convert jpg/png images to WebP and update source file references.
#
# Run from the project root (the directory that contains src/).
#
# Phase 1 — Converts every jpg/png in src/assets/images/ to WebP.
#   Skips files that already have a .webp sibling (intentional fallbacks).
# Phase 2 — Rewrites image path references in all src/ markdown and Astro/JS/TS
#   files, but only for paths whose original was deleted (i.e. actually converted).
#
# Usage:
#   ./compress.sh [--quality N] [--dry-run]
#
# Options:
#   --quality N   WebP quality 1–100 (default: 82)
#   --dry-run     Show what would change without touching any files
#
# Requirements: cwebp (brew install webp), perl (macOS built-in)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

check_deps cwebp perl

QUALITY=82
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quality|-q)
      [[ -n "${2:-}" ]] || { echo "ERROR: --quality requires a value" >&2; exit 1; }
      QUALITY="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

ROOT="$(pwd)"
IMAGES_DIR="$ROOT/src/assets/images"
SRC_DIR="$ROOT/src"
CODE_EXTS=(md mdx astro ts js tsx jsx)

if [[ ! -d "$IMAGES_DIR" ]]; then
  echo "ERROR: Images directory not found: $IMAGES_DIR" >&2
  echo "Run from a project root containing src/assets/images/" >&2
  exit 1
fi

file_size() {
  if stat -f%z "$1" &>/dev/null; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

$DRY_RUN && echo "[dry-run] No files will be modified."
echo ""

# ── Phase 1: Convert ──────────────────────────────────────────────────────────
echo "=== Phase 1: Converting images to WebP ==="
echo ""

converted=0 skipped=0 failed=0
total_orig=0 total_new=0
declare -a converted_rels=()

while IFS= read -r -d '' file; do
  ext="${file##*.}"
  ext_lower="${ext,,}"
  [[ "$ext_lower" == "jpg" || "$ext_lower" == "jpeg" || "$ext_lower" == "png" ]] || continue

  webp="${file%.*}.webp"
  base="$(basename "$file")"

  if [[ -f "$webp" ]]; then
    echo "skip  $base  (.webp sibling already exists — kept as fallback)"
    skipped=$((skipped + 1))
    continue
  fi

  orig_size=$(file_size "$file")
  total_orig=$((total_orig + orig_size))

  if $DRY_RUN; then
    echo "would convert  ${file#${ROOT}/}  ($((orig_size / 1024)) KB)"
    converted_rels+=("${file#${SRC_DIR}/}")
    converted=$((converted + 1))
    continue
  fi

  if cwebp -q "$QUALITY" "$file" -o "$webp" -quiet 2>/dev/null; then
    new_size=$(file_size "$webp")
    total_new=$((total_new + new_size))
    rm "$file"
    converted_rels+=("${file#${SRC_DIR}/}")
    pct=$(( orig_size > 0 ? (orig_size - new_size) * 100 / orig_size : 0 ))
    echo "✓  ${file#${ROOT}/}  $((orig_size / 1024)) KB → $((new_size / 1024)) KB  (−${pct}%)"
    converted=$((converted + 1))
  else
    echo "✗  ${file#${ROOT}/}: conversion failed"
    failed=$((failed + 1))
  fi
done < <(find "$IMAGES_DIR" -type f -print0 | sort -z)

# ── Phase 2: Update references ────────────────────────────────────────────────
echo ""
echo "=== Phase 2: Updating image path references ==="
echo ""

if [[ ${#converted_rels[@]} -eq 0 ]]; then
  echo "  No files converted — nothing to update."
else
  # Build find expression for code files
  declare -a find_name_args=()
  for i in "${!CODE_EXTS[@]}"; do
    [[ $i -gt 0 ]] && find_name_args+=(-o)
    find_name_args+=(-name "*.${CODE_EXTS[$i]}")
  done

  files_updated=0

  while IFS= read -r -d '' src_file; do
    needs_update=false
    for orig_rel in "${converted_rels[@]}"; do
      stem="${orig_rel%.*}"
      ext_lower="${orig_rel##*.}"
      ext_lower="${ext_lower,,}"
      escaped_stem=$(printf '%s' "$stem" | perl -pe 's/([^A-Za-z0-9_\/\-])/\\$1/g')
      if grep -qiE "${escaped_stem}\.(jpg|jpeg|png)" "$src_file" 2>/dev/null; then
        needs_update=true
        break
      fi
    done

    if $needs_update; then
      if ! $DRY_RUN; then
        for orig_rel in "${converted_rels[@]}"; do
          stem="${orig_rel%.*}"
          perl -i -pe "s|\Q${stem}\E\\.(?:jpg|jpeg|png)|${stem}.webp|gi" "$src_file" 2>/dev/null || true
        done
      fi
      echo "${DRY_RUN:+would update  }${src_file#${ROOT}/}"
      files_updated=$((files_updated + 1))
    fi
  done < <(find "$SRC_DIR" -type f \( "${find_name_args[@]}" \) -print0 | sort -z)
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
if $DRY_RUN; then
  echo "Would convert : $converted images"
  echo "Would skip    : $skipped (already have .webp sibling)"
  echo "Would update  : ${files_updated:-0} source files"
else
  saved=$((total_orig - total_new))
  saved_mb=$(awk "BEGIN {printf \"%.1f\", $saved / 1048576}")
  saved_pct=$(( total_orig > 0 ? saved * 100 / total_orig : 0 ))
  echo "Converted : $converted   Skipped : $skipped   Failed : $failed"
  echo "Space saved   : ${saved_mb} MB (${saved_pct}% overall)"
  echo "Source files updated : ${files_updated:-0}"
fi
