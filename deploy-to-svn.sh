#!/usr/bin/env bash
# deploy-to-svn.sh — Build and deploy a plugin to WordPress.org SVN.
#
# Steps:
#   1. composer zip  → <GITHUB_DIR>/[plugin]/build/[plugin].zip
#   2. Unzip         → <GITHUB_DIR>/[plugin]/build/[plugin]/
#   3. svn update    → sync working copy with server
#   4. Clear trunk   → <SVN_BASE>/[plugin]/trunk/
#   5. Copy build    → trunk/
#   6. Create tag    → tags/[version]/
#   7. svn rm        → remove locally-deleted files
#   8. svn add       → stage new/changed files
#
# Usage:
#   ./deploy-to-svn.sh [--dry-run] [--skip-zip] [--commit] plugin-name
#
# Examples:
#   ./deploy-to-svn.sh better-search
#   ./deploy-to-svn.sh --commit better-search
#   ./deploy-to-svn.sh --dry-run better-search
#   ./deploy-to-svn.sh --skip-zip --commit better-search
#
# Configuration: edit config.sh to set GITHUB_DIR, SVN_BASE, and PLUGINS_FREE.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

check_deps svn composer rsync unzip

DRY_RUN=false
SKIP_ZIP=false
DO_COMMIT=false
TARGET=""

usage() {
  echo "Usage: ./deploy-to-svn.sh [--dry-run] [--skip-zip] [--commit] plugin-name"
  echo ""
  echo "Options:"
  echo "  --dry-run     Preview all steps without executing"
  echo "  --skip-zip    Skip composer zip (reuse existing build/)"
  echo "  --commit      Run svn commit after staging changes (default: stage only)"
  echo ""
  echo "Plugins:"
  printf "  %s\n" "${PLUGINS_FREE[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h) usage; exit 0 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    --skip-zip)  SKIP_ZIP=true; shift ;;
    --commit)    DO_COMMIT=true; shift ;;
    -*)          echo "Unknown option: $1" >&2; echo ""; usage >&2; exit 1 ;;
    *)           TARGET="$1"; shift ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  usage
  exit 0
fi

valid=false
for p in "${PLUGINS_FREE[@]}"; do
  [[ "$p" == "$TARGET" ]] && valid=true && break
done
if [[ "$valid" == false ]]; then
  echo "ERROR: No plugin found for '$TARGET'" >&2
  printf "Valid names:\n"
  printf "  %s\n" "${PLUGINS_FREE[@]}"
  exit 1
fi

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "    [dry-run] $*"
  else
    "$@"
  fi
}

deploy_plugin() {
  local plugin="$1"
  local plugin_dir="$GITHUB_DIR/$plugin"
  local build_dir="$plugin_dir/build"
  local build_zip="$build_dir/$plugin.zip"
  local build_src="$build_dir/$plugin"
  local svn_dir="$SVN_BASE/$plugin"
  local trunk_dir="$svn_dir/trunk"
  local tags_dir="$svn_dir/tags"

  if [[ ! -d "$plugin_dir" ]]; then
    echo "  ERROR: $plugin_dir not found" >&2
    return 1
  fi
  if [[ ! -d "$svn_dir" ]]; then
    echo "  ERROR: SVN directory not found: $svn_dir" >&2
    return 1
  fi

  local main_php="$plugin_dir/$plugin.php"
  if [[ ! -f "$main_php" ]]; then
    echo "  ERROR: Main plugin file not found: $main_php" >&2
    return 1
  fi
  local version
  version=$(grep -m1 '^\s*\* Version:' "$main_php" | sed 's/.*Version:[[:space:]]*//' | tr -d '[:space:]')
  if [[ -z "$version" ]]; then
    echo "  ERROR: Could not detect version from $main_php" >&2
    return 1
  fi
  echo "  Version: $version"

  echo "  [1/8] Running composer zip..."
  if [[ "$SKIP_ZIP" == false ]]; then
    run composer zip --working-dir="$plugin_dir"
  else
    echo "    Skipped (--skip-zip)"
  fi

  if [[ "$DRY_RUN" == false && ! -f "$build_zip" ]]; then
    echo "  ERROR: Expected zip not found: $build_zip" >&2
    return 1
  fi

  echo "  [2/8] Unzipping $build_zip..."
  run rm -rf "$build_src"
  run mkdir -p "$build_src"
  run unzip "$build_zip" -d "$build_src"
  if [[ "$DRY_RUN" == false ]]; then
    local file_count
    file_count=$(find "$build_src" -type f | wc -l | tr -d ' ')
    echo "    Extracted $file_count files to $build_src"
  fi

  echo "  [3/8] Updating SVN working copy..."
  run svn update "$svn_dir"

  echo "  [4/8] Clearing trunk..."
  if [[ "$DRY_RUN" == false ]]; then
    local trunk_count
    trunk_count=$(find "$trunk_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
    echo "    Removing $trunk_count items from $trunk_dir"
  fi
  run find "$trunk_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  echo "  [5/8] Copying build to trunk..."
  run rsync -av "$build_src/" "$trunk_dir/"
  if [[ "$DRY_RUN" == false ]]; then
    local trunk_file_count
    trunk_file_count=$(find "$trunk_dir" -type f | wc -l | tr -d ' ')
    echo "    trunk now contains $trunk_file_count files"
  fi

  local tag_dir="$tags_dir/$version"
  echo "  [6/8] Creating tag $version at $tag_dir..."
  if [[ -d "$tag_dir" ]]; then
    echo "  WARN: Tag $version already exists — overwriting"
  fi
  run mkdir -p "$tag_dir"
  run rsync -av "$build_src/" "$tag_dir/"
  if [[ "$DRY_RUN" == false ]]; then
    local tag_file_count
    tag_file_count=$(find "$tag_dir" -type f | wc -l | tr -d ' ')
    echo "    tag/$version now contains $tag_file_count files"
  fi

  echo "  [7/8] Removing deleted files from SVN..."
  if [[ "$DRY_RUN" == false ]]; then
    (
      cd "$svn_dir"
      deleted=$(svn status | sed -e '/^!/!d' -e 's/^! *//')
      if [[ -n "$deleted" ]]; then
        echo "    Files to remove:"
        echo "$deleted" | sed 's/^/      /'
        # shellcheck disable=SC2086
        svn rm $deleted
      else
        echo "    (nothing to remove)"
      fi
    )
  else
    echo "    [dry-run] svn rm \$(svn status | sed -e '/^!/!d' -e 's/^! *//')"
  fi

  echo "  [8/8] Staging new/changed files..."
  if [[ "$DRY_RUN" == false ]]; then
    (
      cd "$svn_dir"
      svn add --force * --auto-props --parents --depth infinity
      local added_count
      added_count=$(svn status | grep -c '^A' || true)
      echo "    $added_count files staged for addition"
    )
  else
    echo "    [dry-run] svn add --force * --auto-props --parents --depth infinity"
  fi

  if [[ "$DO_COMMIT" == true ]]; then
    echo "  [+] Committing to SVN (version $version)..."
    run svn commit "$svn_dir" -m "Release $version"
  else
    echo "  Staged. Run: svn commit $svn_dir -m \"Release $version\""
  fi

  echo "  Cleaning up $build_src..."
  run rm -rf "$build_src"
}

echo "══════════════════════════════════════════"
echo "  $TARGET$([ "$DRY_RUN" == true ] && echo "  [DRY RUN]")"
echo "══════════════════════════════════════════"

deploy_plugin "$TARGET"

echo "  Done."
echo ""
