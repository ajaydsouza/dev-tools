#!/usr/bin/env bash
# deploy-to-github.sh — Verify versions and create a GitHub release for a plugin.
#
# Usage:
#   ./deploy-to-github.sh <plugin-name>               # verify + release
#   ./deploy-to-github.sh --check-only <plugin-name>  # verify only, no release
#
# Checks performed:
#   - readme.txt Stable tag
#   - Changelog entry for that version
#   - Plugin header Version: matches stable tag
#   - *_VERSION constant matches stable tag
#
# Configuration: edit config.sh to set GITHUB_DIR and GITHUB_ORG.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

check_deps gh

CHECK_ONLY=false
DELETE_RELEASE=""
PLUGIN=""

usage() {
  echo "Usage: ./deploy-to-github.sh <plugin-name> [--check-only]"
  echo "       ./deploy-to-github.sh <plugin-name> --delete-release <tag>"
  echo ""
  echo "Options:"
  echo "  --check-only             Verify versions only; do not create a GitHub release"
  echo "  --delete-release <tag>   Delete an existing release and its tag (e.g. v3.0.0)"
  echo ""
  echo "Checks performed:"
  echo "  - readme.txt Stable tag"
  echo "  - Changelog entry for that version"
  echo "  - Plugin header Version: matches stable tag"
  echo "  - *_VERSION constant matches stable tag"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h) usage; exit 0 ;;
    --check-only) CHECK_ONLY=true; shift ;;
    --delete-release) DELETE_RELEASE="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; echo ""; usage >&2; exit 1 ;;
    *) PLUGIN="$1"; shift ;;
  esac
done

if [[ -z "$PLUGIN" ]]; then
  usage >&2
  exit 1
fi

PLUGIN_DIR="$GITHUB_DIR/$PLUGIN"
echo "Plugin directory: $PLUGIN_DIR"
if [[ ! -d "$PLUGIN_DIR" ]]; then
  echo "ERROR: Plugin directory not found: $PLUGIN_DIR" >&2
  exit 1
fi

# ── Delete release ────────────────────────────────────────────────────────────
if [[ -n "$DELETE_RELEASE" ]]; then
  echo "Deleting GitHub release and tag: $DELETE_RELEASE from $GITHUB_ORG/$PLUGIN"
  gh release delete "$DELETE_RELEASE" --repo "$GITHUB_ORG/$PLUGIN" --yes --cleanup-tag
  echo "Deleted release and tag $DELETE_RELEASE from $GITHUB_ORG/$PLUGIN"
  exit 0
fi

ERRORS=0
fail() { echo "  FAIL: $1" >&2; ERRORS=$((ERRORS + 1)); }
pass() { echo "  OK:   $1"; }

# ── readme.txt ───────────────────────────────────────────────────────────────
echo ""
echo "── Checking readme.txt ─────────────────────"
README_TXT="$PLUGIN_DIR/readme.txt"
echo "Reading: $README_TXT"
if [[ ! -f "$README_TXT" ]]; then
  echo "ERROR: readme.txt not found" >&2
  exit 1
fi

VERSION=$(grep -m1 "^Stable tag:" "$README_TXT" | sed 's/Stable tag:[[:space:]]*//' | tr -d '[:space:]')
if [[ -z "$VERSION" ]]; then
  echo "ERROR: Could not find 'Stable tag' in readme.txt" >&2
  exit 1
fi
pass "Stable tag: $VERSION"

echo "Looking for changelog entry: = $VERSION ="
if grep -qE "^= ${VERSION}[[:space:]]*=" "$README_TXT"; then
  pass "Changelog entry for $VERSION exists"
else
  fail "Missing changelog entry for $VERSION"
fi

# ── plugin PHP ────────────────────────────────────────────────────────────────
echo ""
echo "── Checking main plugin PHP file ───────────"
PLUGIN_PHP="$PLUGIN_DIR/$PLUGIN.php"
if [[ ! -f "$PLUGIN_PHP" && "$PLUGIN" == *-pro ]]; then
  PLUGIN_PHP="$PLUGIN_DIR/${PLUGIN%-pro}.php"
fi
if [[ ! -f "$PLUGIN_PHP" ]]; then
  echo "ERROR: Main plugin file not found: $PLUGIN_PHP" >&2
  exit 1
fi
PHP_LABEL="$(basename "$PLUGIN_PHP")"
echo "Reading: $PLUGIN_PHP"

echo "Checking plugin header Version field..."
PHP_HEADER_VER=$(grep -m1 "^ \* Version:" "$PLUGIN_PHP" | sed 's/.*Version:[[:space:]]*//' | tr -d '[:space:]')
if [[ "$PHP_HEADER_VER" == "$VERSION" ]]; then
  pass "$PHP_LABEL header Version: $PHP_HEADER_VER"
else
  fail "$PHP_LABEL header Version: '$PHP_HEADER_VER' (expected '$VERSION')"
fi

echo "Checking *_VERSION constant..."
CONST_LINE=$(grep -m1 "define[[:space:]]*([[:space:]]*'[A-Z_]*VERSION'" "$PLUGIN_PHP" || true)
if [[ -z "$CONST_LINE" ]]; then
  fail "$PHP_LABEL no *_VERSION constant found"
else
  CONST_NAME=$(echo "$CONST_LINE" | sed "s/.*define[[:space:]]*([[:space:]]*'\([A-Z_]*VERSION\)'.*/\1/")
  CONST_VAL=$(echo "$CONST_LINE"  | sed "s/.*VERSION'[[:space:]]*,[[:space:]]*'\([^']*\)'.*/\1/")
  if [[ "$CONST_VAL" == "$VERSION" ]]; then
    pass "$CONST_NAME: $CONST_VAL"
  else
    fail "$CONST_NAME: '$CONST_VAL' (expected '$VERSION')"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
if [[ $ERRORS -gt 0 ]]; then
  echo "FAIL: $ERRORS check(s) failed — fix the issues above before releasing." >&2
  exit 1
fi
echo "All checks passed for $PLUGIN v$VERSION"

[[ "$CHECK_ONLY" == true ]] && exit 0

# ── Create GitHub release ─────────────────────────────────────────────────────
echo ""
echo "── Extracting changelog from readme.txt ────"
CHANGELOG_BODY=$(awk \
  "/^= ${VERSION}[[:space:]]*=/{found=1; next} found && /^= [0-9]/{exit} found{print}" \
  "$README_TXT" | sed '/^[[:space:]]*$/d')

if [[ -z "$CHANGELOG_BODY" ]]; then
  echo "ERROR: Could not extract changelog for $VERSION from readme.txt" >&2
  exit 1
fi

PREV_VERSION=$(grep -E "^= [0-9]" "$README_TXT" | grep -v "^= ${VERSION}" | head -1 | sed 's/= //; s/ =//' | tr -d '[:space:]' || true)
echo "Previous version: ${PREV_VERSION:-none found}"

CHANGELOG="## Changelog
${CHANGELOG_BODY}"

if [[ -n "$PREV_VERSION" ]]; then
  CHANGELOG="${CHANGELOG}

**Full Changelog**: https://github.com/${GITHUB_ORG}/${PLUGIN}/compare/v${PREV_VERSION}...v${VERSION}"
fi

echo "Release notes ($(echo "$CHANGELOG" | wc -l | tr -d ' ') lines):"
echo "$CHANGELOG"

echo ""
echo "── Creating GitHub release ─────────────────"
TAG="v$VERSION"
echo "Repository: $GITHUB_ORG/$PLUGIN"
echo "Tag:        $TAG"

echo "Checking if release $TAG already exists..."
if gh release view "$TAG" --repo "$GITHUB_ORG/$PLUGIN" &>/dev/null; then
  echo "ERROR: Release $TAG already exists for $GITHUB_ORG/$PLUGIN" >&2
  exit 1
fi
echo "No existing release found — proceeding."

echo "Running: gh release create $TAG --repo $GITHUB_ORG/$PLUGIN --title $TAG"
gh release create "$TAG" \
  --repo "$GITHUB_ORG/$PLUGIN" \
  --title "$TAG" \
  --notes "$CHANGELOG"
echo "Release created."

# ── Poll for zip asset ────────────────────────────────────────────────────────
echo ""
echo "── Waiting for zip asset ───────────────────"
ZIP_NAME="${PLUGIN}.zip"
MAX_WAIT=600
ELAPSED=0
INTERVAL=30
echo "Expecting asset: $ZIP_NAME"
echo "Will poll every ${INTERVAL}s, timeout after ${MAX_WAIT}s"
echo ""

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  echo "Polling release assets... (${ELAPSED}s elapsed)"
  ASSETS=$(gh release view "$TAG" --repo "$GITHUB_ORG/$PLUGIN" --json assets --jq '.assets[].name' 2>/dev/null || true)
  if [[ -n "$ASSETS" ]]; then
    echo "  Assets found: $ASSETS"
  else
    echo "  No assets yet."
  fi
  if echo "$ASSETS" | grep -q "^${ZIP_NAME}$"; then
    echo ""
    echo "────────────────────────────────────────────"
    echo "Zip asset confirmed: $ZIP_NAME attached to release $TAG"
    gh release view "$TAG" --repo "$GITHUB_ORG/$PLUGIN" --json url --jq '"Release URL: " + .url'
    exit 0
  fi
  echo "  $ZIP_NAME not yet attached — sleeping ${INTERVAL}s..."
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""
echo "WARNING: Timed out after ${MAX_WAIT}s — $ZIP_NAME not yet attached." >&2
gh release view "$TAG" --repo "$GITHUB_ORG/$PLUGIN" --json url --jq '"Release URL: " + .url'
exit 1
