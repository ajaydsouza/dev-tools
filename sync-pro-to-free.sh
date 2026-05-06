#!/usr/bin/env bash
# sync-pro-to-free.sh — Sync shared code from a pro plugin to its free counterpart.
#
# Steps per plugin pair:
#   1. Overwrite includes/ in free with pro's includes/
#   2. Delete includes/pro/ from free
#   3. Strip pro conditional from includes/class-main.php
#   4. Copy main plugin PHP, stripping: "Update URI", "@fs_premium_only", " Pro" from Plugin Name
#
# Usage:
#   ./sync-pro-to-free.sh <plugin-name>
#   ./sync-pro-to-free.sh --all
#
# Configuration: edit config.sh to set GITHUB_DIR and PLUGINS_PAIRS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

check_deps rsync python3 git

usage() {
  echo "Usage: ./sync-pro-to-free.sh <plugin-name>"
  echo "       ./sync-pro-to-free.sh --all"
  echo ""
  echo "Options:"
  echo "  --all          Sync all configured pairs"
  echo ""
  echo "Configured pairs (edit config.sh to change):"
  for pair in "${PLUGINS_PAIRS[@]}"; do
    read -r pro free _ <<< "$pair"
    echo "  $pro → $free"
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

patch_class_main() {
  local file="$1"
  FILE="$file" python3 << 'PYEOF'
import os, re

filepath = os.environ['FILE']
with open(filepath, encoding='utf-8') as f:
    lines = f.readlines()

result = []
i = 0
while i < len(lines):
    line = lines[i]

    if line.strip() == '// Initialize pro features.':
        i += 1
        continue

    if re.search(r'_freemius\(\)->is__premium_only\(\)', line):
        depth = line.count('{') - line.count('}')
        i += 1
        while i < len(lines) and depth > 0:
            depth += lines[i].count('{') - lines[i].count('}')
            i += 1
        if i < len(lines) and lines[i].strip() == '':
            i += 1
        continue

    result.append(line)
    i += 1

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(result)

print(f"  Patched {filepath}")
PYEOF
}

patch_main_php() {
  local file="$1"
  FILE="$file" python3 << 'PYEOF'
import os, re

filepath = os.environ['FILE']
with open(filepath, encoding='utf-8') as f:
    content = f.read()

content = re.sub(r'(\* Plugin Name:.+?) Pro\s*$', r'\1', content, flags=re.MULTILINE)
content = re.sub(r' \* Update URI:[^\n]*\n', '', content)
content = re.sub(r' \*\n \* @fs_premium_only[^\n]*\n', '', content)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"  Patched {filepath}")
PYEOF
}

sync_pair() {
  local pro="$1"
  local free="$2"
  local main_php="$3"

  local pro_dir="$GITHUB_DIR/$pro"
  local free_dir="$GITHUB_DIR/$free"

  echo "══════════════════════════════════════════"
  echo "  $pro  →  $free"
  echo "══════════════════════════════════════════"

  echo "  [1/5] Syncing includes/..."
  rsync -a --delete "$pro_dir/includes/" "$free_dir/includes/"

  echo "  [2/5] Removing includes/pro/..."
  rm -rf "$free_dir/includes/pro"

  echo "  [3/5] Patching class-main.php..."
  patch_class_main "$free_dir/includes/class-main.php"

  echo "  [4/5] Syncing root files..."
  rsync -a \
    --exclude='.DS_Store' \
    --exclude='.freemius.conf' \
    --exclude='.gitignore' \
    --exclude='load-freemius.php' \
    --exclude="$main_php" \
    --exclude='*/' \
    "$pro_dir/" "$free_dir/"

  echo "  [5/5] Copying and stripping $main_php..."
  cp "$pro_dir/$main_php" "$free_dir/$main_php"
  patch_main_php "$free_dir/$main_php"

  echo "  Done."
  echo ""
}

matched=false
for pair in "${PLUGINS_PAIRS[@]}"; do
  read -r pro free main_php <<< "$pair"
  if [[ -z "$TARGET" || "$TARGET" == "$free" || "$TARGET" == "$pro" ]]; then
    sync_pair "$pro" "$free" "$main_php"
    matched=true
  fi
done

if [[ -n "$TARGET" && "$matched" == false ]]; then
  echo "ERROR: No plugin pair found for '$TARGET'" >&2
  echo "Configured pairs (edit config.sh to change):" >&2
  for pair in "${PLUGINS_PAIRS[@]}"; do
    read -r pro free _ <<< "$pair"
    echo "  $pro → $free" >&2
  done
  exit 1
fi
