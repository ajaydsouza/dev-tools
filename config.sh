#!/usr/bin/env bash
# config.sh — Shared configuration for dev-tools scripts.
#
# All scripts in this directory source this file automatically.
# Override any value by setting the variable in your environment before
# calling a script, or by editing this file directly.

_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Paths ─────────────────────────────────────────────────────────────────────

# Root directory containing all plugin repos (parent of this dev-tools dir by default)
GITHUB_DIR="${GITHUB_DIR:-$(dirname "$_TOOLS_DIR")}"

# GitHub organisation or user that owns the plugin repos
GITHUB_ORG="${GITHUB_ORG:-YourOrg}"

# Freemius API base URL
API_BASE="${API_BASE:-https://api.freemius.com/v1}"

# SVN working copy base (used by deploy-to-svn.sh)
SVN_BASE="${SVN_BASE:-${HOME}/Documents/Dev/wporgsvn}"

# Local WordPress test site plugin directories (used by deploy-plugin.sh)
SITE_NETWORK="${SITE_NETWORK:-${HOME}/Documents/Dev/Sites/wp-network/wp-content/plugins}"
SITE_SINGLE="${SITE_SINGLE:-${HOME}/Documents/Dev/Sites/wpstaging.lcl/wp-content/plugins}"
SITE_WZLCL="${SITE_WZLCL:-${HOME}/Documents/Dev/Sites/webberz0ne.lcl/htdocs/wp-content/plugins}"

# Upscayl binary and models paths (used by upscale.sh)
UPSCAYL_BIN="${UPSCAYL_BIN:-/Applications/Upscayl.app/Contents/Resources/bin/upscayl-bin}"
UPSCAYL_MODELS="${UPSCAYL_MODELS:-/Applications/Upscayl.app/Contents/Resources/models}"

# ── Plugin registries ─────────────────────────────────────────────────────────

# All plugins including pro variants — used by deploy-plugin.sh
PLUGINS_ALL=(
  better-search
  better-search-pro
  contextual-related-posts
  contextual-related-posts-pro
  knowledgebase
  knowledgebase-pro
  top-10
  top-10-pro
  add-to-all
  autoclose
  popular-authors
  webberzone-code-block-highlighting
  webberzone-link-warnings
  where-did-they-go-from-here
  wzn-invoicing
  freemkit
)

# Free-only plugins — used by deploy-to-svn.sh
PLUGINS_FREE=(
  better-search
  contextual-related-posts
  knowledgebase
  top-10
  add-to-all
  autoclose
  popular-authors
  webberzone-code-block-highlighting
  webberzone-link-warnings
  where-did-they-go-from-here
)

# Free/pro pairs — used by sync-pro-to-free.sh
# Format: "pro-slug free-slug main-php-filename"
PLUGINS_PAIRS=(
  "better-search-pro better-search better-search.php"
  "contextual-related-posts-pro contextual-related-posts contextual-related-posts.php"
  "knowledgebase-pro knowledgebase knowledgebase.php"
  "top-10-pro top-10 top-10.php"
)

# Language file plugin registry — used by update-language-files.sh
# Format: "dir text-domain type"  (type = pro | free | standalone)
PLUGINS_LANG=(
  "better-search-pro                   better-search                      pro"
  "better-search                       better-search                      free"
  "contextual-related-posts-pro        contextual-related-posts           pro"
  "contextual-related-posts            contextual-related-posts           free"
  "knowledgebase-pro                   knowledgebase                      pro"
  "knowledgebase                       knowledgebase                      free"
  "top-10-pro                          top-10                             pro"
  "top-10                              top-10                             free"
  "where-did-they-go-from-here         where-did-they-go-from-here        standalone"
  "popular-authors                     popular-authors                    standalone"
  "add-to-all                          add-to-all                         standalone"
  "autoclose                           autoclose                          standalone"
  "webberzone-code-block-highlighting  webberzone-code-block-highlighting standalone"
  "webberzone-link-warnings            webberzone-link-warnings           standalone"
  "wzn-invoicing                       wzn-invoicing                      standalone"
  "freemkit                            freemkit                           standalone"
)

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
