#!/usr/bin/env node
// Usage: node scripts/compress.js [--quality N] [--dry-run]
//
// Phase 1 — Converts every jpg/png in src/assets/images/ to WebP.
//   Skips files that already have a .webp sibling (intentional fallbacks, e.g. <picture>).
// Phase 2 — Rewrites image path references in all src/ markdown and Astro/JS/TS files,
//   but only for paths whose original file was deleted (i.e. actually converted).
//
// Options:
//   --quality N   WebP quality 1–100 (default: 82)
//   --dry-run     Show what would change without touching any files

import sharp from "sharp";
import fs from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const IMAGES_DIR = path.join(ROOT, "src", "assets", "images");
const SRC_DIR = path.join(ROOT, "src");

const CONVERT_EXT = new Set([".jpg", ".jpeg", ".png"]);
const CODE_EXT = new Set([".md", ".mdx", ".astro", ".ts", ".js", ".tsx", ".jsx"]);

const args = process.argv.slice(2);
let quality = 82;
let dryRun = false;

for (let i = 0; i < args.length; i++) {
  if ((args[i] === "--quality" || args[i] === "-q") && args[i + 1]) {
    quality = Number(args[++i]);
  } else if (args[i] === "--dry-run") {
    dryRun = true;
  } else {
    console.error(`Unknown option: ${args[i]}`);
    process.exit(1);
  }
}

function walk(dir, allowedExt, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, allowedExt, out);
    else if (!allowedExt || allowedExt.has(path.extname(entry.name).toLowerCase()))
      out.push(full);
  }
  return out;
}

async function main() {
  if (dryRun) console.log("[dry-run] No files will be modified.\n");

  // ── Phase 1: Convert ──────────────────────────────────────────────────────
  console.log("=== Phase 1: Converting images to WebP ===\n");

  const imageFiles = walk(IMAGES_DIR, CONVERT_EXT);
  let converted = 0, skipped = 0, failed = 0;
  let totalOrigBytes = 0, totalNewBytes = 0;

  // Track which absolute webp paths were newly created, so Phase 2 knows what to update.
  const newWebpPaths = new Set();

  for (const file of imageFiles) {
    const ext = path.extname(file).toLowerCase();
    const webpPath = file.slice(0, -ext.length) + ".webp";

    if (fs.existsSync(webpPath)) {
      console.log(`skip  ${path.basename(file)}  (.webp sibling already exists — kept as fallback)`);
      skipped++;
      continue;
    }

    const origSize = fs.statSync(file).size;
    totalOrigBytes += origSize;

    if (dryRun) {
      console.log(`would convert  ${path.relative(ROOT, file)}  (${(origSize / 1024).toFixed(0)} KB)`);
      newWebpPaths.add(webpPath);
      converted++;
      continue;
    }

    try {
      await sharp(file).webp({ quality }).toFile(webpPath);
      const newSize = fs.statSync(webpPath).size;
      totalNewBytes += newSize;
      fs.unlinkSync(file);
      newWebpPaths.add(webpPath);
      const pct = Math.round((1 - newSize / origSize) * 100);
      console.log(
        `✓  ${path.relative(ROOT, file)}  ${(origSize / 1024).toFixed(0)} KB → ${(newSize / 1024).toFixed(0)} KB  (−${pct}%)`
      );
      converted++;
    } catch (e) {
      console.error(`✗  ${path.relative(ROOT, file)}: ${e.message}`);
      failed++;
    }
  }

  // ── Phase 2: Update references ────────────────────────────────────────────
  console.log("\n=== Phase 2: Updating image path references ===\n");

  // Matches relative paths to assets/images with a convertible extension.
  // Group 1: everything up to and including the filename stem
  // Group 2: the old extension (jpg | jpeg | png)
  const PATH_RE = /((?:\.\.\/)*assets\/images\/[^\s"'`>]+?)\.(jpg|jpeg|png)/gi;

  const codeFiles = walk(SRC_DIR, CODE_EXT);
  let filesUpdated = 0;

  for (const file of codeFiles) {
    const content = fs.readFileSync(file, "utf8");
    let changed = false;

    const updated = content.replace(PATH_RE, (match, base, oldExt) => {
      const webpAbs = path.resolve(path.dirname(file), base + ".webp");
      const origAbs = path.resolve(path.dirname(file), base + "." + oldExt);

      if (dryRun) {
        if (newWebpPaths.has(webpAbs)) {
          changed = true;
          return base + ".webp";
        }
        return match;
      }

      // Only rewrite if the original was deleted (i.e. we converted it) and webp now exists.
      if (!fs.existsSync(origAbs) && fs.existsSync(webpAbs)) {
        changed = true;
        return base + ".webp";
      }
      return match;
    });

    if (changed) {
      if (!dryRun) fs.writeFileSync(file, updated);
      console.log(`${dryRun ? "would update" : "updated"}  ${path.relative(ROOT, file)}`);
      filesUpdated++;
    }
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n=== Summary ===");
  if (dryRun) {
    console.log(`Would convert : ${converted} images`);
    console.log(`Would skip    : ${skipped} (already have .webp sibling)`);
    console.log(`Would update  : ${filesUpdated} source files`);
  } else {
    const savedMB = ((totalOrigBytes - totalNewBytes) / 1024 / 1024).toFixed(1);
    const savedPct = totalOrigBytes > 0 ? Math.round((1 - totalNewBytes / totalOrigBytes) * 100) : 0;
    console.log(`Converted : ${converted}   Skipped : ${skipped}   Failed : ${failed}`);
    console.log(`Space saved   : ${savedMB} MB (${savedPct}% overall)`);
    console.log(`Source files updated : ${filesUpdated}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
