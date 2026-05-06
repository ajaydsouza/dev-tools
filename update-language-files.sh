#!/usr/bin/env bash
# update-language-files.sh — Regenerate .pot, update .po, and compile .mo files.
#
# For pro-to-free plugins, both the pro and free versions are updated.
# After updating, changes that consist only of date/timestamp header updates
# (no actual string changes) are automatically discarded.
#
# Usage:
#   ./update-language-files.sh                          # show usage
#   ./update-language-files.sh --all                    # update all plugins
#   ./update-language-files.sh better-search            # update one plugin (both pro and free)
#
# Configuration: edit config.sh to set GITHUB_DIR and PLUGINS_LANG.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

check_deps wp git

usage() {
  echo "Usage: ./update-language-files.sh <plugin-name>"
  echo "       ./update-language-files.sh --all"
  echo ""
  echo "Options:"
  echo "  --all          Update all plugins"
  echo ""
  echo "Configured plugins (edit config.sh to change):"
  for entry in "${PLUGINS_LANG[@]}"; do
    read -r dir _ _type <<< "$entry"
    echo "  $dir ($( [[ "$_type" == "standalone" ]] && echo standalone || echo "$_type" ))"
  done
}

TARGET=""
case "${1:-}" in
  --help | -h) usage; exit 0 ;;
  --all)       TARGET="" ;;
  "")          usage; exit 0 ;;
  -*)          echo "Unknown option: $1" >&2; echo ""; usage >&2; exit 1 ;;
  *)           TARGET="${1}" ;;
esac

only_metadata_changed() {
  local dir="$1"
  local diff
  diff="$(git -C "$dir" diff -- languages/ 2>/dev/null || true)"
  [[ -z "$diff" ]] && return 0
  local meaningful
  meaningful="$(echo "$diff" \
    | grep '^[+-]' \
    | grep -v '^[+-][+-][+-]' \
    | grep -Ev '^[+-]("POT-Creation-Date|"PO-Revision-Date|"X-Generator)' \
    || true)"
  [[ -z "$meaningful" ]]
}

update_plugin() {
  local dir="$1"
  local domain="$2"
  local type="$3"
  local plugin_dir="$GITHUB_DIR/$dir"
  local lang_dir="$plugin_dir/languages"

  echo "  ── $dir"

  if [[ ! -d "$plugin_dir" ]]; then
    echo "     WARNING: directory not found, skipping."
    return
  fi

  if [[ ! -d "$lang_dir" ]]; then
    mkdir -p "$lang_dir"
  fi

  local extra_args=()
  if [[ "$type" == "pro" ]]; then
    extra_args+=(--headers="{\"Report-Msgid-Bugs-To\":\"https://wordpress.org/support/plugin/$domain\"}")
  fi

  wp i18n make-pot "$plugin_dir" "$lang_dir/$domain.pot" --quiet "${extra_args[@]+"${extra_args[@]}"}"
  wp i18n update-po "$lang_dir/$domain.pot" "$lang_dir" --quiet 2>/dev/null || true
  wp i18n make-mo "$lang_dir" --quiet 2>/dev/null || true

  if only_metadata_changed "$plugin_dir"; then
    git -C "$plugin_dir" checkout -- languages/ 2>/dev/null || true
    echo "     No string changes — discarded metadata-only diff."
  else
    echo "     Language files updated."
  fi
}

should_process() {
  local dir="$1"
  [[ -z "$TARGET" ]] && return 0
  local base="${dir%-pro}"
  [[ "$TARGET" == "$dir" || "$TARGET" == "$base" ]]
}

matched=false
prev_base=""

for entry in "${PLUGINS_LANG[@]}"; do
  read -r dir domain _type <<< "$entry"

  should_process "$dir" || continue
  matched=true

  base="${dir%-pro}"
  if [[ "$base" != "$prev_base" ]]; then
    echo ""
    echo "══════════════════════════════════════════"
    echo "  ${base}"
    echo "══════════════════════════════════════════"
    prev_base="$base"
  fi

  update_plugin "$dir" "$domain" "$_type"
done

echo ""

if [[ -n "$TARGET" && "$matched" == false ]]; then
  echo "ERROR: No plugin found for '$TARGET'" >&2
  echo "Configured plugin dirs (edit config.sh to add more):" >&2
  for entry in "${PLUGINS_LANG[@]}"; do
    read -r dir _ _ <<< "$entry"
    echo "  $dir" >&2
  done
  exit 1
fi

echo "Done."
