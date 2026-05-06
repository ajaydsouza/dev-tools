#!/usr/bin/env bash
# release-plugin.sh — Full release pipeline for a WordPress plugin.
#
# Usage:
#   ./release-plugin.sh <plugin-name>
#   ./release-plugin.sh --dry-run <plugin-name>
#
# Pipeline (in order):
#   1. deploy-to-freemius  (pro plugins only; leaves release as pending)
#   2. update-language-files
#   3. deploy-to-github
#   4. deploy-to-svn       (stages adds/removes; commit manually)
#
# Configuration: edit config.sh to set GITHUB_DIR and GITHUB_ORG.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

check_deps git

PLUGIN=""
DRY_RUN=false

usage() {
  echo "Usage: ./release-plugin.sh <plugin-name> [--dry-run]"
  echo ""
  echo "Options:"
  echo "  --dry-run    Preview all steps without making changes"
  echo ""
  echo "Pipeline (in order):"
  echo "  1. deploy-to-freemius   Pro plugins only; release left as pending"
  echo "  2. update-language-files"
  echo "  3. deploy-to-github"
  echo "  4. deploy-to-svn        Stages adds/removes only; commit manually"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h) usage; exit 0 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    -*)          echo "Unknown option: $1" >&2; echo ""; usage >&2; exit 1 ;;
    *)           PLUGIN="$1"; shift ;;
  esac
done

if [[ -z "$PLUGIN" ]]; then
  usage
  exit 1
fi

IS_PRO=false
FREE_PLUGIN="$PLUGIN"
if [[ "$PLUGIN" == *-pro ]]; then
  IS_PRO=true
  FREE_PLUGIN="${PLUGIN%-pro}"
fi

DRY_RUN_FLAG=""
[[ "$DRY_RUN" == true ]] && DRY_RUN_FLAG="--dry-run"

echo "════════════════════════════════════════════"
echo "Release pipeline: $PLUGIN"
[[ "$DRY_RUN" == true ]] && echo "(dry run)"
echo "════════════════════════════════════════════"

# ── Step 1: deploy-to-freemius (pro only) ─────────────────────────────────────
echo ""
echo "── Step 1: Deploy to Freemius ──────────────"
if [[ "$IS_PRO" == true ]]; then
  "$SCRIPT_DIR/deploy-to-freemius.sh" "$PLUGIN" ${DRY_RUN_FLAG}
else
  echo "  Skipped (free plugin)"
fi

# ── Step 2: update-language-files ─────────────────────────────────────────────
echo ""
echo "── Step 2: Update language files ───────────"
"$SCRIPT_DIR/update-language-files.sh" "$FREE_PLUGIN"

# ── Step 2b: commit any language file changes ─────────────────────────────────
FREE_REPO="$GITHUB_DIR/$FREE_PLUGIN"
if [[ "$DRY_RUN" == false ]] && ! git -C "$FREE_REPO" diff --quiet -- languages/ 2>/dev/null; then
  echo "  Committing language file changes in $FREE_PLUGIN..."
  git -C "$FREE_REPO" add languages/
  git -C "$FREE_REPO" commit -m "Update language files"
  echo "  Committed."
fi

PRO_REPO="$GITHUB_DIR/$PLUGIN"
if [[ "$IS_PRO" == true && "$DRY_RUN" == false ]] && ! git -C "$PRO_REPO" diff --quiet -- languages/ 2>/dev/null; then
  echo "  Committing language file changes in $PLUGIN..."
  git -C "$PRO_REPO" add languages/
  git -C "$PRO_REPO" commit -m "Update language files"
  echo "  Committed."
fi

# ── Step 3: deploy-to-github ──────────────────────────────────────────────────
echo ""
echo "── Step 3: Deploy to GitHub ────────────────"
"$SCRIPT_DIR/deploy-to-github.sh" "$PLUGIN"

# ── Step 4: deploy-to-svn ─────────────────────────────────────────────────────
echo ""
echo "── Step 4: Deploy to SVN (stage only) ──────"
"$SCRIPT_DIR/deploy-to-svn.sh" ${DRY_RUN_FLAG} "$FREE_PLUGIN"

echo ""
echo "════════════════════════════════════════════"
echo "Pipeline complete: $PLUGIN"
echo "Next: review SVN changes and commit manually"
[[ "$IS_PRO" == true ]] && echo "Next: promote Freemius release when ready"
echo "════════════════════════════════════════════"
