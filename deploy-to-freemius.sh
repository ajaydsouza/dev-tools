#!/usr/bin/env bash
# =============================================================================
# deploy-to-freemius.sh
#
# Automates the Freemius deployment workflow:
#   1.  Strip "Pro" from plugin name header
#   2.  Build zip
#   3.  Restore plugin name
#   4.  Upload to Freemius
#   5.  Set release_mode
#   6.  Download pro + free zips
#   7.  Validate free zip folder name
#   8.  Unzip to respective GitHub dirs
#   9.  Run phpcbf on both
#   10. Auto-revert free/includes/class-main.php
#   11. Show remaining phpcs errors for manual review
#
# Usage:
#   ./deploy-to-freemius.sh <plugin-slug> [--release released|beta|pending] [--dry-run]
#   ./deploy-to-freemius.sh <plugin-slug> --tag-id <id>   # skip upload, use existing tag
#   ./deploy-to-freemius.sh <plugin-slug> --delete-tag <tag-id>
#
# Config per plugin:
#   <GITHUB_DIR>/<slug>-pro/.freemius.conf  — must export FREEMIUS_PRODUCT_ID and FREEMIUS_API_TOKEN
#
# Requirements: curl, jq, unzip, phpcbf, phpcs, composer
#
# Configuration: edit config.sh to set GITHUB_DIR and API_BASE.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}==>${NC} $*"; }
success() { echo -e "${GREEN}  ✓${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
error()   { echo -e "${RED}  ✗${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Defaults ──────────────────────────────────────────────────────────────────
RELEASE_MODE="pending"
DRY_RUN=false
DELETE_TAG=""
SKIP_UPLOAD_TAG_ID=""

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  echo "Usage: ./deploy-to-freemius.sh <plugin-slug> [options]"
  echo "       ./deploy-to-freemius.sh <plugin-slug> --tag-id <id>"
  echo "       ./deploy-to-freemius.sh <plugin-slug> --delete-tag <id>"
  echo ""
  echo "Options:"
  echo "  --release released|beta|pending   Set Freemius release mode (default: pending)"
  echo "  --dry-run                         Preview steps without making changes"
  echo "  --tag-id <id>                     Skip upload; use an existing Freemius tag ID"
  echo "  --delete-tag <id>                 Delete a Freemius tag and exit"
  echo ""
  echo "Config: <GITHUB_DIR>/<slug>-pro/.freemius.conf must export FREEMIUS_PRODUCT_ID and FREEMIUS_API_TOKEN"
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

case "$1" in
  --help | -h) usage; exit 0 ;;
esac

PLUGIN_SLUG="${1%-pro}"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h)  usage; exit 0 ;;
    --release)    RELEASE_MODE="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --delete-tag) DELETE_TAG="$2"; shift 2 ;;
    --tag-id)     SKIP_UPLOAD_TAG_ID="$2"; shift 2 ;;
    *)            die "Unknown argument: $1" ;;
  esac
done

[[ "${RELEASE_MODE}" =~ ^(released|beta|pending)$ ]] \
  || die "Invalid --release value '${RELEASE_MODE}'. Must be: released, beta, or pending"

# ── Derive paths from slug ─────────────────────────────────────────────────────
PRO_DEST_DIR="${GITHUB_DIR}/${PLUGIN_SLUG}-pro"
FREE_DEST_DIR="${GITHUB_DIR}/${PLUGIN_SLUG}"
MAIN_FILE="${PRO_DEST_DIR}/${PLUGIN_SLUG}.php"

# ── Per-plugin config ──────────────────────────────────────────────────────────
PLUGIN_CONFIG="${PRO_DEST_DIR}/.freemius.conf"
if [[ -f "${PLUGIN_CONFIG}" ]]; then
  # shellcheck source=/dev/null
  source "${PLUGIN_CONFIG}"
fi

# ── Validate required vars ─────────────────────────────────────────────────────
: "${FREEMIUS_API_TOKEN:?Set FREEMIUS_API_TOKEN in ${PLUGIN_CONFIG}}"
: "${FREEMIUS_PRODUCT_ID:?Set FREEMIUS_PRODUCT_ID in ${PLUGIN_CONFIG}}"

# ── Optional overrides (with defaults) ────────────────────────────────────────
BUILD_ZIP_CMD="${BUILD_ZIP_CMD:-composer run zip}"
PHPCS_CONFIG="${PHPCS_CONFIG:-phpcs.xml.dist}"
FREE_MAIN_CLASS="${FREE_MAIN_CLASS:-includes/class-main.php}"
FREE_REVERT_PATHS="${FREE_REVERT_PATHS:-languages}"

# ── Derive plugin names from main file header ──────────────────────────────────
if [[ -z "${PLUGIN_NAME_PRO:-}" ]]; then
  PLUGIN_NAME_PRO=$(grep -m1 "^ \* Plugin Name:" "${MAIN_FILE}" | sed 's/.*Plugin Name:[[:space:]]*//' | tr -d '\r')
fi
if [[ -z "${PLUGIN_NAME_BASE:-}" ]]; then
  PLUGIN_NAME_BASE="${PLUGIN_NAME_PRO% Pro}"
fi

# ── Helpers ────────────────────────────────────────────────────────────────────
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    die "Required command not found: $1

Install hints:
  curl     → brew install curl
  jq       → brew install jq
  unzip    → brew install unzip
  phpcbf   → composer global require squizlabs/php_codesniffer
  phpcs    → composer global require squizlabs/php_codesniffer
  composer → brew install composer"
  fi
}

confirm() {
  local prompt="$1"
  read -rp "$(echo -e "${YELLOW}${prompt}${NC} [y/N] ")" answer
  [[ "${answer}" =~ ^[Yy]$ ]]
}

run_phpcbf() {
  local dir="$1"
  info "Running phpcbf in ${dir}"
  (
    cd "${dir}"
    phpcbf -p -v -s --standard="${PHPCS_CONFIG}" $(find . -name '*.php') || true
  )
}

fix_load_freemius() {
  local file="${1}/load-freemius.php"
  [[ -f "${file}" ]] || return 0
  perl -i -0pe 's/<\?php\n\n/<\?php\n/; s/\*\/\nnamespace/*\/\n\nnamespace/' "${file}"
  success "Fixed load-freemius.php file comment spacing"
}

# ── Temp dir + cleanup ─────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
MAIN_FILE_BACKED_UP=false
MAIN_FILE_BAK="${WORK_DIR}/main-plugin-file.bak"

cleanup() {
  if ${MAIN_FILE_BACKED_UP}; then
    cp "${MAIN_FILE_BAK}" "${MAIN_FILE}"
    warn "Restored ${MAIN_FILE} (cleanup)"
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# ── Delete-tag shortcut ────────────────────────────────────────────────────────
if [[ -n "${DELETE_TAG}" ]]; then
  require_cmd curl
  require_cmd jq
  info "Deleting Freemius tag ${DELETE_TAG} for product ${FREEMIUS_PRODUCT_ID}"
  RESPONSE=$(curl -s -X DELETE \
    "${API_BASE}/products/${FREEMIUS_PRODUCT_ID}/tags/${DELETE_TAG}.json" \
    -H "Authorization: Bearer ${FREEMIUS_API_TOKEN}")
  if echo "${RESPONSE}" | jq -e '.error' &>/dev/null; then
    die "Delete failed: $(echo "${RESPONSE}" | jq -r '.error.message')"
  fi
  success "Tag ${DELETE_TAG} deleted"
  exit 0
fi

# ── Validation ─────────────────────────────────────────────────────────────────
require_cmd curl
require_cmd jq
require_cmd unzip
require_cmd phpcbf
require_cmd phpcs

[[ -f "${MAIN_FILE}" ]]     || die "Main plugin file not found: ${MAIN_FILE}"
[[ -d "${PRO_DEST_DIR}" ]]  || die "Pro dir not found: ${PRO_DEST_DIR}"
[[ -d "${FREE_DEST_DIR}" ]] || die "Free dir not found: ${FREE_DEST_DIR}"
[[ -f "${PRO_DEST_DIR}/${PHPCS_CONFIG}" ]]  || warn "phpcs config not found at ${PRO_DEST_DIR}/${PHPCS_CONFIG} — phpcbf will use defaults"
[[ -f "${FREE_DEST_DIR}/${PHPCS_CONFIG}" ]] || warn "phpcs config not found at ${FREE_DEST_DIR}/${PHPCS_CONFIG} — phpcbf will use defaults"

if ${DRY_RUN}; then
  warn "DRY RUN — no changes will be made to Freemius or disk"
fi

echo ""
echo -e "${CYAN}Freemius Deploy: ${NC}${PLUGIN_NAME_PRO} → ${RELEASE_MODE}"
echo "  Product ID : ${FREEMIUS_PRODUCT_ID}"
echo "  Pro dir    : ${PRO_DEST_DIR}"
echo "  Free dir   : ${FREE_DEST_DIR}"
echo ""

if [[ -n "${SKIP_UPLOAD_TAG_ID}" ]]; then
  TAG_ID="${SKIP_UPLOAD_TAG_ID}"
  info "Steps 1-4 skipped — using provided tag ID: ${TAG_ID}"
  LATEST_INFO=$(curl -sf \
    "${API_BASE}/products/${FREEMIUS_PRODUCT_ID}/tags/latest.json" \
    -H "Authorization: Bearer ${FREEMIUS_API_TOKEN}" 2>/dev/null || true)
  VERSION=$(echo "${LATEST_INFO}" | jq -r '.version // "(unknown)"' 2>/dev/null || echo "(unknown)")
  success "Tag ID: ${TAG_ID} (latest on Freemius: v${VERSION})"
else

# ── Step 0: Clean build directory ─────────────────────────────────────────────
info "Step 0: Removing old build directory"
if ! ${DRY_RUN}; then
  rm -rf "${PRO_DEST_DIR}/build/"
  success "Removed ${PRO_DEST_DIR}/build/"
else
  success "[dry-run] Would remove ${PRO_DEST_DIR}/build/"
fi

# ── Step 1: Strip "Pro" from plugin name ──────────────────────────────────────
info "Step 1: Temporarily stripping 'Pro' from plugin name in ${MAIN_FILE}"

if [[ "${PLUGIN_NAME_PRO}" == "${PLUGIN_NAME_BASE}" ]]; then
  success "Plugin name has no 'Pro' suffix — skipping rename"
  SKIP_RENAME=true
else
  SKIP_RENAME=false
  if ! grep -q "Plugin Name: ${PLUGIN_NAME_PRO}" "${MAIN_FILE}"; then
    die "Could not find 'Plugin Name: ${PLUGIN_NAME_PRO}' in ${MAIN_FILE}"
  fi

  if ! ${DRY_RUN}; then
    cp "${MAIN_FILE}" "${MAIN_FILE_BAK}"
    MAIN_FILE_BACKED_UP=true
    sed -i "" "s/Plugin Name: ${PLUGIN_NAME_PRO}/Plugin Name: ${PLUGIN_NAME_BASE}/" "${MAIN_FILE}"
    success "Plugin name updated to '${PLUGIN_NAME_BASE}'"
  else
    success "[dry-run] Would rename plugin header"
  fi
fi

# ── Step 2: Build zip ─────────────────────────────────────────────────────────
info "Step 2: Building zip via: ${BUILD_ZIP_CMD}"

if ! ${DRY_RUN}; then
  (cd "${PRO_DEST_DIR}" && eval "${BUILD_ZIP_CMD}")

  ZIP_FILE="${PRO_DEST_DIR}/build/${PLUGIN_SLUG}-pro.zip"
  if [[ ! -f "${ZIP_FILE}" ]]; then
    ZIP_FILE=$(find "${PRO_DEST_DIR}/build" -maxdepth 1 -name "*.zip" 2>/dev/null \
      -exec ls -t {} + 2>/dev/null | head -1)
    [[ -n "${ZIP_FILE}" ]] || die "Could not locate built zip in ${PRO_DEST_DIR}/build/"
  fi
  ZIP_FILE=$(realpath "${ZIP_FILE}")
  success "Built zip: ${ZIP_FILE}"
else
  ZIP_FILE="dry-run.zip"
  success "[dry-run] Would build zip"
fi

# ── Step 3: Restore plugin name ───────────────────────────────────────────────
if ! ${SKIP_RENAME}; then
  info "Step 3: Restoring plugin name in ${MAIN_FILE}"
  if ! ${DRY_RUN}; then
    cp "${MAIN_FILE_BAK}" "${MAIN_FILE}"
    MAIN_FILE_BACKED_UP=false
    success "Restored '${PLUGIN_NAME_PRO}'"
  else
    success "[dry-run] Would restore plugin header"
  fi
fi

# ── Step 4: Upload to Freemius ─────────────────────────────────────────────────
info "Step 4: Uploading to Freemius (product ${FREEMIUS_PRODUCT_ID})"

if ! ${DRY_RUN}; then
  UPLOAD_RESPONSE=$(curl -s --progress-bar --max-time 300 --retry 3 --retry-delay 5 \
    -X POST \
    "${API_BASE}/products/${FREEMIUS_PRODUCT_ID}/tags.json" \
    -H "Authorization: Bearer ${FREEMIUS_API_TOKEN}" \
    -F "file=@${ZIP_FILE}" \
    || die "Upload request failed")

  UPLOAD_ERROR_CODE=$(echo "${UPLOAD_RESPONSE}" | jq -r '.error.code // empty')

  if [[ "${UPLOAD_ERROR_CODE}" == "duplicate_plugin_version" ]]; then
    DUP_VERSION=$(echo "${UPLOAD_RESPONSE}" | jq -r '.error.data.version // "unknown"')
    EXISTING_TAG=$(curl -sf \
      "${API_BASE}/products/${FREEMIUS_PRODUCT_ID}/tags/latest.json" \
      -H "Authorization: Bearer ${FREEMIUS_API_TOKEN}" 2>/dev/null \
      | jq -r 'if .version == "'"${DUP_VERSION}"'" then .id else "" end' 2>/dev/null || true)
    if [[ -z "${EXISTING_TAG}" ]]; then
      EXISTING_TAG=$(curl -sf \
        "${API_BASE}/products/${FREEMIUS_PRODUCT_ID}/tags.json" \
        -H "Authorization: Bearer ${FREEMIUS_API_TOKEN}" 2>/dev/null \
        | jq -r '.tags // [] | map(select(.version == "'"${DUP_VERSION}"'")) | first | .id // ""' 2>/dev/null || true)
    fi
    if [[ -n "${EXISTING_TAG}" ]]; then
      warn "Version ${DUP_VERSION} already exists (tag ${EXISTING_TAG}) — resuming with that tag"
      TAG_ID="${EXISTING_TAG}"
      VERSION="${DUP_VERSION}"
      HAS_FREE="(existing)"; HAS_PREMIUM="(existing)"
      success "Reusing tag ID: ${TAG_ID} (v${VERSION})"
    else
      die "Version ${DUP_VERSION} already exists on Freemius but tag could not be found.
  Find the tag ID via the Freemius dashboard, then:
    Delete it : $0 ${PLUGIN_SLUG} --delete-tag <tag-id>
    Resume    : $0 ${PLUGIN_SLUG} --tag-id <tag-id>"
    fi
  else
    TAG_ID=$(echo "${UPLOAD_RESPONSE}" | jq -r '.id // empty')
    VERSION=$(echo "${UPLOAD_RESPONSE}" | jq -r '.version // "unknown"')
    HAS_FREE=$(echo "${UPLOAD_RESPONSE}" | jq -r '.has_free')
    HAS_PREMIUM=$(echo "${UPLOAD_RESPONSE}" | jq -r '.has_premium')
    [[ -n "${TAG_ID}" ]] || die "Upload failed — no tag ID in response:\n${UPLOAD_RESPONSE}"
    success "Uploaded v${VERSION} — tag ID: ${TAG_ID} (has_free=${HAS_FREE}, has_premium=${HAS_PREMIUM})"
  fi
else
  TAG_ID="DRY_RUN_TAG"
  VERSION="x.x.x"
  success "[dry-run] Would upload zip"
fi

fi # end SKIP_UPLOAD_TAG_ID

# ── Step 5: Set release_mode ───────────────────────────────────────────────────
info "Step 5: Setting release_mode to '${RELEASE_MODE}'"

if ! ${DRY_RUN}; then
  UPDATE_RESPONSE=$(curl -sf -X PUT \
    "${API_BASE}/products/${FREEMIUS_PRODUCT_ID}/tags/${TAG_ID}.json" \
    -H "Authorization: Bearer ${FREEMIUS_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"release_mode\": \"${RELEASE_MODE}\"}" \
    || die "Failed to update release_mode")

  CONFIRMED_MODE=$(echo "${UPDATE_RESPONSE}" | jq -r '.release_mode')
  success "release_mode confirmed: ${CONFIRMED_MODE}"
else
  success "[dry-run] Would set release_mode=${RELEASE_MODE}"
fi

# ── Step 6: Download pro + free zips ──────────────────────────────────────────
PRO_ZIP="${WORK_DIR}/pro.zip"
FREE_ZIP="${WORK_DIR}/free.zip"

info "Step 6a: Downloading pro zip"
if ! ${DRY_RUN}; then
  curl -fL --progress-bar --max-time 300 --retry 3 --retry-delay 5 \
    -X GET \
    "${API_BASE}/products/${FREEMIUS_PRODUCT_ID}/tags/${TAG_ID}.zip?is_premium=true" \
    -H "Authorization: Bearer ${FREEMIUS_API_TOKEN}" \
    -o "${PRO_ZIP}" \
    || die "Failed to download pro zip"
  success "Downloaded pro zip ($(du -h "${PRO_ZIP}" | cut -f1))"
else
  success "[dry-run] Would download pro zip to ${PRO_ZIP}"
fi

info "Step 6b: Downloading free zip"
if ! ${DRY_RUN}; then
  curl -fL --progress-bar --max-time 300 --retry 3 --retry-delay 5 \
    -X GET \
    "${API_BASE}/products/${FREEMIUS_PRODUCT_ID}/tags/${TAG_ID}.zip?is_premium=false" \
    -H "Authorization: Bearer ${FREEMIUS_API_TOKEN}" \
    -o "${FREE_ZIP}" \
    || die "Failed to download free zip"
  success "Downloaded free zip ($(du -h "${FREE_ZIP}" | cut -f1))"
else
  success "[dry-run] Would download free zip to ${FREE_ZIP}"
fi

# ── Step 7: Validate free zip folder name ─────────────────────────────────────
info "Step 7: Checking free zip for 'Pro' in folder name"
if ! ${DRY_RUN}; then
  FREE_ROOT_DIR=$(unzip -Z1 "${FREE_ZIP}" | { head -1; cat > /dev/null; } | cut -d'/' -f1)
  if echo "${FREE_ROOT_DIR}" | grep -qi "pro"; then
    warn "Free zip root folder is '${FREE_ROOT_DIR}' — contains 'Pro'"
    confirm "Continue anyway?" || die "Aborted by user"
  else
    success "Free zip root folder: ${FREE_ROOT_DIR} (no 'Pro')"
  fi
else
  success "[dry-run] Would verify free zip folder name contains no 'Pro'"
fi

# ── Step 8: Unzip to GitHub dirs ──────────────────────────────────────────────
info "Step 8a: Deploying pro to ${PRO_DEST_DIR}"
if ! ${DRY_RUN}; then
  unzip -q -o "${PRO_ZIP}" -d "${WORK_DIR}/pro"
  PRO_UNZIP_DIR=$(find "${WORK_DIR}/pro" -mindepth 1 -maxdepth 1 -type d | head -1)
  [[ -n "${PRO_UNZIP_DIR}" ]] || die "Could not locate root dir inside pro zip"
  cp -a "${PRO_UNZIP_DIR}/." "${PRO_DEST_DIR}/"
  success "Pro copied from $(basename "${PRO_UNZIP_DIR}")"
else
  success "[dry-run] Would unzip pro zip and copy contents to ${PRO_DEST_DIR}"
fi

info "Step 8b: Deploying free to ${FREE_DEST_DIR}"
if ! ${DRY_RUN}; then
  unzip -q -o "${FREE_ZIP}" -d "${WORK_DIR}/free"
  FREE_UNZIP_DIR=$(find "${WORK_DIR}/free" -mindepth 1 -maxdepth 1 -type d | head -1)
  [[ -n "${FREE_UNZIP_DIR}" ]] || die "Could not locate root dir inside free zip"
  cp -a "${FREE_UNZIP_DIR}/." "${FREE_DEST_DIR}/"
  success "Free copied from $(basename "${FREE_UNZIP_DIR}")"
else
  success "[dry-run] Would unzip free zip and copy contents to ${FREE_DEST_DIR}"
fi

# ── Step 9: phpcbf on pro ─────────────────────────────────────────────────────
info "Step 9: phpcbf on pro"
if ! ${DRY_RUN}; then
  run_phpcbf "${PRO_DEST_DIR}"
  fix_load_freemius "${PRO_DEST_DIR}"
  success "phpcbf complete on pro"
else
  success "[dry-run] Would run phpcbf in ${PRO_DEST_DIR}"
fi

# ── Step 10: phpcbf on free + revert class-main.php ───────────────────────────
info "Step 10: phpcbf on free"
if ! ${DRY_RUN}; then
  run_phpcbf "${FREE_DEST_DIR}"
  fix_load_freemius "${FREE_DEST_DIR}"

  CLASS_MAIN="${FREE_DEST_DIR}/${FREE_MAIN_CLASS}"
  if [[ -f "${CLASS_MAIN}" ]]; then
    if git -C "${FREE_DEST_DIR}" diff --quiet -- "${FREE_MAIN_CLASS}" 2>/dev/null; then
      success "${FREE_MAIN_CLASS} unchanged"
    else
      git -C "${FREE_DEST_DIR}" checkout -- "${FREE_MAIN_CLASS}"
      warn "Auto-reverted ${FREE_MAIN_CLASS} (phpcbf blank-line fixes rejected)"
    fi
  else
    warn "${FREE_MAIN_CLASS} not found — skipping auto-revert"
  fi

  for revert_path in ${FREE_REVERT_PATHS}; do
    if git -C "${FREE_DEST_DIR}" diff --quiet -- "${revert_path}" 2>/dev/null; then
      success "${revert_path} unchanged"
    else
      git -C "${FREE_DEST_DIR}" checkout -- "${revert_path}"
      warn "Auto-reverted ${revert_path} (Freemius overwrote with incorrect files)"
    fi
  done

  info "Step 10b: Regenerating free language files (Freemius always overwrites them)"
  "${SCRIPT_DIR}/update-language-files.sh" "${PLUGIN_SLUG}" 2>/dev/null || true

  success "phpcbf complete on free"
else
  success "[dry-run] Would run phpcbf in ${FREE_DEST_DIR} and auto-revert ${FREE_MAIN_CLASS} and ${FREE_REVERT_PATHS} if changed"
fi

# ── Step 11: Show remaining phpcs errors ──────────────────────────────────────
info "Step 11: Checking for remaining phpcs errors (manual fixes needed)"
echo ""

for label_dir in "PRO:${PRO_DEST_DIR}" "FREE:${FREE_DEST_DIR}"; do
  label="${label_dir%%:*}"
  dir="${label_dir##*:}"
  echo -e "${CYAN}── ${label} (${dir}) ──${NC}"
  if ! ${DRY_RUN}; then
    (
      cd "${dir}"
      phpcs -p -s --standard="${PHPCS_CONFIG}" $(find . -name '*.php') 2>&1 || true
    ) | grep -E "^FILE:|ERROR|WARNING" | head -40 || echo "  (none — or phpcs not run)"
  else
    echo "  [dry-run]"
  fi
  echo ""
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deploy complete — v${VERSION} / tag ${TAG_ID}${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo "Remaining manual steps:"
echo "  1. Fix phpcs errors above (typically blank line after <?php and file docblock)"
echo "  2. Re-run phpcs to confirm clean:"
echo "       (cd ${PRO_DEST_DIR}  && phpcs -p -s --standard=${PHPCS_CONFIG} \$(find . -name '*.php'))"
echo "       (cd ${FREE_DEST_DIR} && phpcs -p -s --standard=${PHPCS_CONFIG} \$(find . -name '*.php'))"
echo "  3. git add + commit both repos"
echo ""
if [[ "${RELEASE_MODE}" == "pending" ]]; then
  warn "Release mode is 'pending'. Promote when ready:"
  echo "  $0 ${PLUGIN_SLUG} --tag-id ${TAG_ID} --release released"
fi
