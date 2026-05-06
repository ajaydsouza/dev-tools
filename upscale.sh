#!/usr/bin/env bash
# upscale.sh — Upscale images using Upscayl.
#
# Folders are scanned recursively for jpg/jpeg/png/webp files.
# Images already at or above the target width are skipped.
#
# Usage:
#   ./upscale.sh [options] <image|folder> [image|folder ...]
#
# Options:
#   --width N      Target width in px (default: 1600)
#   --model NAME   Upscayl model name (default: high-fidelity-4x)
#   --role ROLE    Shorthand for --width: hero=1600, background=2000, content=1200, thumbnail=600
#
# Requirements:
#   Upscayl.app  → https://upscayl.org  (macOS, install to /Applications)
#   sips         → macOS built-in
#
# Override Upscayl path:
#   UPSCAYL_BIN=/path/to/upscayl-bin ./upscale.sh ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

UPSCAYL="${UPSCAYL_BIN:-/Applications/Upscayl.app/Contents/Resources/bin/upscayl-bin}"
MODELS="${UPSCAYL_MODELS:-/Applications/Upscayl.app/Contents/Resources/models}"
DEFAULT_MODEL="high-fidelity-4x"
DEFAULT_WIDTH=1600

declare -A ROLE_WIDTHS=([hero]=1600 [background]=2000 [content]=1200 [thumbnail]=600)

TARGET_WIDTH=$DEFAULT_WIDTH
MODEL=$DEFAULT_MODEL
declare -a INPUTS=()

usage() {
  sed -n '2,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --width|-w)
      [[ -n "${2:-}" ]] || { echo "ERROR: --width requires a value" >&2; exit 1; }
      TARGET_WIDTH="$2"; shift 2 ;;
    --model|-n)
      [[ -n "${2:-}" ]] || { echo "ERROR: --model requires a value" >&2; exit 1; }
      MODEL="$2"; shift 2 ;;
    --role)
      [[ -n "${2:-}" ]] || { echo "ERROR: --role requires a value" >&2; exit 1; }
      role="$2"; shift 2
      if [[ -z "${ROLE_WIDTHS[$role]+x}" ]]; then
        echo "Unknown role '$role'. Valid: ${!ROLE_WIDTHS[*]}" >&2
        exit 1
      fi
      TARGET_WIDTH="${ROLE_WIDTHS[$role]}"
      ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  INPUTS+=("$1"); shift ;;
  esac
done

if [[ ${#INPUTS[@]} -eq 0 ]]; then
  usage >&2
  exit 1
fi

# Check macOS sips (dimension reading)
if ! command -v sips &>/dev/null; then
  echo "ERROR: sips not found — this script requires macOS." >&2
  exit 1
fi

# Check Upscayl binary
if [[ ! -f "$UPSCAYL" ]]; then
  echo "ERROR: Upscayl binary not found at: $UPSCAYL" >&2
  echo "" >&2
  echo "  Install Upscayl from https://upscayl.org" >&2
  echo "  Or set: UPSCAYL_BIN=/path/to/upscayl-bin" >&2
  exit 1
fi

get_width() {
  sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/{print $2}'
}

choose_scale() {
  local w=$1 target=$2
  for s in 2 3 4; do
    if (( w * s >= target )); then echo $s; return; fi
  done
  echo 4
}

output_format() {
  local ext="${1##*.}"
  ext="${ext,,}"
  case "$ext" in
    jpeg) echo "jpg" ;;
    jpg|png|webp) echo "$ext" ;;
    *) echo "jpg" ;;
  esac
}

declare -a collected_files=()

collect_files() {
  local path="$1"
  if [[ -d "$path" ]]; then
    while IFS= read -r -d '' f; do
      local ext="${f##*.}"
      case "${ext,,}" in
        jpg|jpeg|png|webp) collected_files+=("$f") ;;
      esac
    done < <(find "$path" -type f -print0 | sort -z)
  elif [[ -f "$path" ]]; then
    local ext="${path##*.}"
    case "${ext,,}" in
      jpg|jpeg|png|webp) collected_files+=("$path") ;;
    esac
  fi
}

for input in "${INPUTS[@]}"; do
  abs="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
  if [[ ! -e "$abs" ]]; then
    echo "Not found: $input" >&2
    exit 1
  fi
  collect_files "$abs"
done

if [[ ${#collected_files[@]} -eq 0 ]]; then
  echo "No supported image files found (jpg, jpeg, png, webp)." >&2
  exit 1
fi

skipped=0 processed=0 failed=0

for file in "${collected_files[@]}"; do
  width=$(get_width "$file")
  if [[ -z "$width" ]]; then
    echo "Could not read dimensions: $file" >&2
    failed=$((failed + 1))
    continue
  fi

  if (( width >= TARGET_WIDTH )); then
    echo "✓  $(basename "$file")  (${width}px) already ≥ ${TARGET_WIDTH}px — skipped"
    skipped=$((skipped + 1))
    continue
  fi

  scale=$(choose_scale "$width" "$TARGET_WIDTH")
  fmt=$(output_format "$file")

  echo "↑  $(basename "$file")  (${width}px) → ${scale}x upscale → ${TARGET_WIDTH}px wide"

  if "$UPSCAYL" \
    -i "$file" \
    -o "$file" \
    -m "$MODELS" \
    -n "$MODEL" \
    -z "$scale" \
    -w "$TARGET_WIDTH" \
    -f "$fmt"; then
    processed=$((processed + 1))
  else
    echo "Failed: $file" >&2
    failed=$((failed + 1))
  fi
done

declare -a parts=()
[[ $processed -gt 0 ]] && parts+=("$processed upscaled")
[[ $skipped   -gt 0 ]] && parts+=("$skipped skipped")
[[ $failed    -gt 0 ]] && parts+=("$failed failed")
if [[ ${#parts[@]} -gt 0 ]]; then
  echo ""
  ( IFS=', '; echo "Done: ${parts[*]}." )
fi
