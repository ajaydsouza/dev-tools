#!/usr/bin/env bash
# config.sh — Shared configuration for dev-tools scripts.
#
# All scripts in this directory source this file automatically.
# Override any value by setting the variable in your environment before
# calling a script, or by editing this file directly.

_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Local overrides ───────────────────────────────────────────────────────────
# config.local.sh is gitignored — put your personal paths and tokens there.
# It is sourced before any defaults below, so its values take precedence.
_LOCAL_CONFIG="$_TOOLS_DIR/config.local.sh"
# shellcheck source=/dev/null
[[ -f "$_LOCAL_CONFIG" ]] && source "$_LOCAL_CONFIG"

# ── Paths ─────────────────────────────────────────────────────────────────────

# Root directory containing all plugin repos (parent of this dev-tools dir by default)
GITHUB_DIR="${GITHUB_DIR:-$(dirname "$_TOOLS_DIR")}"

# GitHub organisation or user that owns the plugin repos
GITHUB_ORG="${GITHUB_ORG:-YourOrg}"

# Freemius API base URL
API_BASE="${API_BASE:-https://api.freemius.com/v1}"

# SVN working copy base (used by deploy-to-svn.sh)
# e.g. SVN_BASE="$HOME/svn"
SVN_BASE="${SVN_BASE:-}"

# Local WordPress test site plugin directories (used by deploy-plugin.sh)
# e.g. SITE_NETWORK="$HOME/Sites/mynetwork/wp-content/plugins"
SITE_NETWORK="${SITE_NETWORK:-}"
SITE_SINGLE="${SITE_SINGLE:-}"
SITE_WZLCL="${SITE_WZLCL:-}"

# Upscayl binary and models paths (used by upscale.sh)
UPSCAYL_BIN="${UPSCAYL_BIN:-/Applications/Upscayl.app/Contents/Resources/bin/upscayl-bin}"
UPSCAYL_MODELS="${UPSCAYL_MODELS:-/Applications/Upscayl.app/Contents/Resources/models}"

# ── Plugin registries ─────────────────────────────────────────────────────────
# Define these in config.local.sh:
#
#   PLUGINS_ALL=(my-plugin my-plugin-pro ...)        # all plugins incl. pro — deploy-plugin.sh
#   PLUGINS_FREE=(my-plugin ...)                     # free only — deploy-to-svn.sh
#   PLUGINS_PAIRS=("my-plugin-pro my-plugin my-plugin.php" ...)  # sync-pro-to-free.sh
#   PLUGINS_LANG=("my-plugin my-plugin free" ...)   # "dir domain type" — update-language-files.sh

# ── Dependency checker ────────────────────────────────────────────────────────

check_deps() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  echo "ERROR: Missing required tools: ${missing[*]}" >&2
  echo "" >&2
  echo "Install hints:" >&2
  for cmd in "${missing[@]}"; do
    case "$cmd" in
      gh)        echo "  gh        → brew install gh" >&2 ;;
      jq)        echo "  jq        → brew install jq" >&2 ;;
      svn)       echo "  svn       → brew install subversion" >&2 ;;
      wp)        echo "  wp-cli    → brew install wp-cli" >&2 ;;
      composer)  echo "  composer  → brew install composer" >&2 ;;
      phpcbf)    echo "  phpcbf    → composer global require squizlabs/php_codesniffer" >&2 ;;
      phpcs)     echo "  phpcs     → composer global require squizlabs/php_codesniffer" >&2 ;;
      rsync)     echo "  rsync     → brew install rsync" >&2 ;;
      cwebp)     echo "  cwebp     → brew install webp" >&2 ;;
      node)      echo "  node      → brew install node" >&2 ;;
      python3)   echo "  python3   → brew install python3" >&2 ;;
      curl)      echo "  curl      → brew install curl" >&2 ;;
      unzip)     echo "  unzip     → brew install unzip" >&2 ;;
      perl)      echo "  perl      → brew install perl" >&2 ;;
      sips)      echo "  sips      → macOS built-in (this script requires macOS)" >&2 ;;
      git)       echo "  git       → brew install git" >&2 ;;
      bc)        echo "  bc        → brew install bc" >&2 ;;
      *)         echo "  $cmd      → install manually" >&2 ;;
    esac
  done
  exit 1
}
