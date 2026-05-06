#!/usr/bin/env bash
# deploy-plugin.sh — Sync plugins between the GitHub workspace and WordPress test sites.
#
# Default: push includes/ only (repo → site). Use --pull to reverse, --all for full plugin.
#
# Usage:
#   ./deploy-plugin.sh [--pull] [--all] [--site network|single|wzlcl|all] plugin-name
#
# Examples:
#   ./deploy-plugin.sh better-search                          # push includes/ to all sites
#   ./deploy-plugin.sh --all better-search                    # push full plugin to all sites
#   ./deploy-plugin.sh --site network top-10                  # push includes/ to wpnetwork only
#   ./deploy-plugin.sh --pull better-search                   # pull includes/ from all sites → repo
#   ./deploy-plugin.sh --pull --all --site single top-10-pro  # pull full plugin from wpsingle only
#
# Configuration: edit config.sh to set GITHUB_DIR, SITE_*, and PLUGINS_ALL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

check_deps rsync

RSYNC_EXCLUDES=(
  --exclude='.git/'
  --exclude='.github/'
  --exclude='.DS_Store'
  --exclude='*.map'
  --exclude='node_modules/'
  --exclude='phpunit/'
  --exclude='phpcompat-tools/'
  --exclude='wporg-assets/'
  --include='vendor/freemius/'
  --include='vendor/freemius/***'
  --exclude='vendor/*'
  --exclude='.freemius.conf'
)

DIRECTION="push"
SITE="all"
INCLUDES_ONLY=true
TARGET=""

usage() {
  echo "Usage: ./deploy-plugin.sh [--pull] [--all] [--site network|single|wzlcl|all] [plugin-name]"
  echo ""
  echo "Options:"
  echo "  --pull              Copy from site → repo (default: repo → site)"
  echo "  --all               Sync full plugin (default: includes/ only)"
  echo "  --site network      Target wpnetwork.test only"
  echo "  --site single       Target wpsingle.test only"
  echo "  --site wzlcl        Target webberz0ne.lcl only"
  echo "  --site all          Target all sites (default)"
  echo ""
  echo "  plugin-name         Sync this plugin only (omit to list plugins)"
  echo ""
  echo "Plugins:"
  printf "  %s\n" "${PLUGINS_ALL[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h) usage; exit 0 ;;
    --pull)      DIRECTION="pull"; shift ;;
    --push)      DIRECTION="push"; shift ;;
    --site)      SITE="$2"; shift 2 ;;
    --all)       INCLUDES_ONLY=false; shift ;;
    -*)          echo "Unknown option: $1" >&2; echo ""; usage >&2; exit 1 ;;
    *)           TARGET="$1"; shift ;;
  esac
done

if [[ "$SITE" != "network" && "$SITE" != "single" && "$SITE" != "wzlcl" && "$SITE" != "all" ]]; then
  echo "ERROR: --site must be network, single, wzlcl, or all" >&2
  exit 1
fi

if [[ -z "$TARGET" ]]; then
  usage
  exit 0
fi

sync_plugin() {
  local plugin="$1"
  local site_dir="$2"
  local site_label="$3"
  local repo_dir="$GITHUB_DIR/$plugin"
  local site_plugin_dir="$site_dir/$plugin"

  if [[ ! -d "$repo_dir" ]]; then
    echo "  SKIP: $repo_dir not found"
    return
  fi

  local src dst label_suffix=""
  if [[ "$INCLUDES_ONLY" == true ]]; then
    src="$repo_dir/includes/"
    dst="$site_plugin_dir/includes/"
    label_suffix=" (includes/)"
  else
    src="$repo_dir/"
    dst="$site_plugin_dir/"
  fi

  if [[ "$DIRECTION" == "push" ]]; then
    if [[ ! -d "$site_plugin_dir" ]]; then
      echo "  SKIP: $site_plugin_dir not found"
      return
    fi
    echo "  → $site_label$label_suffix"
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$src" "$dst"
  else
    if [[ ! -d "$site_plugin_dir" ]]; then
      echo "  SKIP: $site_plugin_dir not found"
      return
    fi
    echo "  ← $site_label$label_suffix"
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$dst" "$src"
  fi
}

matched=false
for plugin in "${PLUGINS_ALL[@]}"; do
  [[ "$TARGET" != "$plugin" ]] && continue

  echo "══════════════════════════════════════════"
  echo "  $plugin  [${DIRECTION}]"
  echo "══════════════════════════════════════════"

  if [[ "$SITE" == "network" || "$SITE" == "all" ]]; then
    sync_plugin "$plugin" "$SITE_NETWORK" "wpnetwork.test"
  fi
  if [[ "$SITE" == "single" || "$SITE" == "all" ]]; then
    sync_plugin "$plugin" "$SITE_SINGLE" "wpsingle.test"
  fi
  if [[ "$SITE" == "wzlcl" || "$SITE" == "all" ]]; then
    sync_plugin "$plugin" "$SITE_WZLCL" "webberz0ne.lcl"
  fi

  echo "  Done."
  echo ""
  matched=true
done

if [[ "$matched" == false ]]; then
  echo "ERROR: No plugin found for '$TARGET'" >&2
  printf "Valid names:\n"
  printf "  %s\n" "${PLUGINS_ALL[@]}"
  exit 1
fi
