# dev-tools

A collection of shell scripts for WordPress plugin development workflows — releases, deployments, SVN, language files, image processing, and local site syncing.

## Setup

```bash
git clone https://github.com/ajaydsouza/dev-tools.git
cd dev-tools
chmod +x *.sh
```

Edit `config.sh` to match your environment:

```bash
GITHUB_DIR="/path/to/your/plugin/repos"   # default: parent of this directory
GITHUB_ORG="YourOrg"                       # GitHub org or user owning the repos
SVN_BASE="$HOME/path/to/wporgsvn"          # WordPress.org SVN working copies
SITE_NETWORK="..."                          # local wp-content/plugins paths
SITE_SINGLE="..."
SITE_WZLCL="..."
```

Update the `PLUGINS_*` arrays in `config.sh` to reflect your plugins.

---

## WordPress scripts

All scripts source `config.sh` automatically from their own directory.

### `release-plugin.sh` — Full release pipeline

```bash
./release-plugin.sh <plugin-name>          # run full pipeline
./release-plugin.sh --dry-run <plugin-name>
```

Orchestrates: Freemius deploy (pro only) → language files → GitHub release → SVN staging.

### `deploy-to-github.sh` — GitHub release

```bash
./deploy-to-github.sh <plugin-name>               # verify + create release + wait for zip
./deploy-to-github.sh --check-only <plugin-name>  # verify versions only
```

Checks `readme.txt` stable tag, changelog entry, plugin header `Version:`, and `*_VERSION` constant. Creates a `vX.Y.Z` GitHub release with the changelog, then polls for a zip asset.

### `deploy-to-freemius.sh` — Freemius upload

```bash
./deploy-to-freemius.sh <plugin-slug> [--release released|beta|pending] [--dry-run]
./deploy-to-freemius.sh <plugin-slug> --tag-id <id>      # skip upload, use existing tag
./deploy-to-freemius.sh <plugin-slug> --delete-tag <id>  # delete a Freemius tag
```

Strips "Pro" from plugin name → builds zip → restores name → uploads to Freemius → downloads pro+free zips → unzips → runs `phpcbf` on both → auto-reverts `class-main.php` and `languages/` in the free copy.

**Config per plugin:** `<GITHUB_DIR>/<slug>-pro/.freemius.conf` must export `FREEMIUS_PRODUCT_ID` and `FREEMIUS_API_TOKEN`. This file is never committed.

### `deploy-to-svn.sh` — WordPress.org SVN

```bash
./deploy-to-svn.sh [--dry-run] [--skip-zip] [--commit] plugin-name
```

Builds the plugin zip, unzips it, syncs to the SVN working copy, creates a version tag, stages adds/removes, and optionally commits. Free plugins only.

### `deploy-plugin.sh` — Sync to local test sites

```bash
./deploy-plugin.sh [--pull] [--all] [--site network|single|wzlcl|all] plugin-name
```

Rsyncs plugin code between the repo and local WordPress test sites. Default: push `includes/` only. `--all` syncs the full plugin. `--pull` reverses direction.

### `sync-pro-to-free.sh` — Sync pro → free

```bash
./sync-pro-to-free.sh --all              # sync all configured pairs
./sync-pro-to-free.sh better-search      # sync one pair only
```

Copies non-pro `includes/` from a pro plugin to its free counterpart, removes `includes/pro/`, patches `class-main.php` to strip the Freemius gate, and strips `Update URI` / `@fs_premium_only` / ` Pro` from the main plugin PHP file.

### `update-language-files.sh` — Regenerate i18n files

```bash
./update-language-files.sh --all             # update all plugins
./update-language-files.sh better-search     # update one plugin
```

Runs `wp i18n make-pot`, `update-po`, and `make-mo`. Auto-discards diffs that contain only metadata header changes with no real string changes.

---

## Image scripts

### `compress.sh` — Convert images to WebP

```bash
./compress.sh [--quality N] [--dry-run]
```

Run from the project root (must contain `src/assets/images/`).

- Phase 1: converts every jpg/png in `src/assets/images/` to WebP (skips files that already have a `.webp` sibling)
- Phase 2: rewrites image path references in all `src/` markdown and Astro/JS/TS files for converted images

**Requires:** `cwebp` (`brew install webp`), `perl` (macOS built-in)

A Node.js equivalent (`compress.js`) is also included for projects using `sharp`. Requires `node` and the `sharp` package.

### `upscale.sh` — Upscale images with Upscayl

```bash
./upscale.sh [--width N] [--role ROLE] [--model NAME] <image|folder> [...]
```

**Roles:** `hero` (1600px), `background` (2000px), `content` (1200px), `thumbnail` (600px)

Images already at or above the target width are skipped.

**Requires:** [Upscayl](https://upscayl.org) installed to `/Applications/Upscayl.app`, `sips` (macOS built-in)

Override the Upscayl path: `UPSCAYL_BIN=/path/to/upscayl-bin ./upscale.sh ...`

A Node.js equivalent (`upscale.js`) is also included.

> **Note:** `upscale.sh` and `upscale.js` are macOS-only (Upscayl + `sips`).

---

## Dependencies

| Script | Requirements |
|--------|-------------|
| `deploy-to-github.sh` | `gh` (GitHub CLI) |
| `deploy-to-freemius.sh` | `curl`, `jq`, `unzip`, `phpcbf`, `phpcs`, `composer` |
| `deploy-to-svn.sh` | `svn`, `composer`, `rsync`, `unzip` |
| `deploy-plugin.sh` | `rsync` |
| `update-language-files.sh` | `wp` (WP-CLI), `git` |
| `sync-pro-to-free.sh` | `rsync`, `python3`, `git` |
| `release-plugin.sh` | `git` (delegates to other scripts for their own deps) |
| `compress.sh` | `cwebp`, `perl` |
| `upscale.sh` | Upscayl.app, `sips` (macOS) |

Install missing tools: `brew install <name>`. Each script prints install hints if a dependency is missing.

---

## License

MIT
