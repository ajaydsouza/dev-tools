#!/usr/bin/env node
// Usage: node scripts/upscale.js [options] <image|folder> [image|folder ...]
//
// Options:
//   --width N      Target width in px (default: 1600)
//   --model NAME   Upscayl model name (default: high-fidelity-4x)
//   --role ROLE    Shorthand for --width: hero=1600, background=2000, content=1200, thumbnail=600
//
// Folders are scanned recursively for jpg/jpeg/png/webp files.
// Images already at or above the target width are skipped.

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const UPSCAYL = "/Applications/Upscayl.app/Contents/Resources/bin/upscayl-bin";
const MODELS = "/Applications/Upscayl.app/Contents/Resources/models";
const DEFAULT_MODEL = "high-fidelity-4x";
const DEFAULT_WIDTH = 1600;

const ROLE_WIDTHS = {
  hero: 1600,
  background: 2000,
  content: 1200,
  thumbnail: 600,
};

function getDimensions(file) {
  const raw = execFileSync("sips", ["-g", "pixelWidth", "-g", "pixelHeight", file], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  const w = raw.match(/pixelWidth:\s+(\d+)/);
  const h = raw.match(/pixelHeight:\s+(\d+)/);
  if (!w || !h) throw new Error(`Could not read dimensions for ${file}`);
  return { width: Number(w[1]), height: Number(h[1]) };
}

// Minimum scale factor whose output width meets or exceeds the target.
// Prefers lower scales (less computation, less overshoot) since upscayl-bin
// will resize the result to --width exactly regardless.
function chooseScale(currentWidth, targetWidth) {
  for (const scale of [2, 3, 4]) {
    if (currentWidth * scale >= targetWidth) return scale;
  }
  return 4;
}

const IMAGE_EXT = new Set([".jpg", ".jpeg", ".png", ".webp"]);

function collectFiles(inputPath, out = []) {
  const stat = fs.statSync(inputPath);
  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(inputPath, { withFileTypes: true })) {
      collectFiles(path.join(inputPath, entry.name), out);
    }
  } else if (IMAGE_EXT.has(path.extname(inputPath).toLowerCase())) {
    out.push(inputPath);
  }
  return out;
}

function outputFormat(file) {
  const ext = path.extname(file).slice(1).toLowerCase();
  if (ext === "jpeg") return "jpg";
  if (["jpg", "png", "webp"].includes(ext)) return ext;
  return "jpg";
}

// Parse args
const args = process.argv.slice(2);
let targetWidth = DEFAULT_WIDTH;
let model = DEFAULT_MODEL;
const inputs = [];

for (let i = 0; i < args.length; i++) {
  if ((args[i] === "--width" || args[i] === "-w") && args[i + 1]) {
    targetWidth = Number(args[++i]);
  } else if ((args[i] === "--model" || args[i] === "-n") && args[i + 1]) {
    model = args[++i];
  } else if (args[i] === "--role" && args[i + 1]) {
    const role = args[++i];
    if (!ROLE_WIDTHS[role]) {
      console.error(`Unknown role "${role}". Valid roles: ${Object.keys(ROLE_WIDTHS).join(", ")}`);
      process.exit(1);
    }
    targetWidth = ROLE_WIDTHS[role];
  } else if (args[i].startsWith("-")) {
    console.error(`Unknown option: ${args[i]}`);
    process.exit(1);
  } else {
    inputs.push(args[i]);
  }
}

if (!inputs.length) {
  console.error(
    "Usage: node scripts/upscale.js [--width N] [--role hero|background|content|thumbnail] [--model NAME] <image|folder> [...]"
  );
  process.exit(1);
}

// Expand folders into individual image files
const files = [];
for (const input of inputs) {
  const abs = path.resolve(input);
  if (!fs.existsSync(abs)) {
    console.error(`Not found: ${input}`);
    process.exit(1);
  }
  collectFiles(abs, files);
}

if (!files.length) {
  console.error("No supported image files found (jpg, jpeg, png, webp).");
  process.exit(1);
}

if (!fs.existsSync(UPSCAYL)) {
  console.error("Upscayl binary not found at:", UPSCAYL);
  process.exit(1);
}

let skipped = 0;
let processed = 0;
let failed = 0;

for (const file of files) {
  const abs = path.resolve(file);

  let dims;
  try {
    dims = getDimensions(abs);
  } catch (e) {
    console.error(`Could not read dimensions: ${file}`);
    failed++;
    continue;
  }

  const { width, height } = dims;

  if (width >= targetWidth) {
    console.log(`✓  ${path.basename(file)}  (${width}×${height}) already ≥ ${targetWidth}px — skipped`);
    skipped++;
    continue;
  }

  const scale = chooseScale(width, targetWidth);
  const format = outputFormat(abs);

  console.log(
    `↑  ${path.basename(file)}  (${width}×${height}) → ${scale}x upscale → ${targetWidth}px wide`
  );

  try {
    execFileSync(
      UPSCAYL,
      [
        "-i", abs,
        "-o", abs,
        "-m", MODELS,
        "-n", model,
        "-z", String(scale),
        "-w", String(targetWidth),
        "-f", format,
      ],
      { stdio: "inherit" }
    );
    processed++;
  } catch (e) {
    console.error(`Failed: ${file}`);
    failed++;
  }
}

const parts = [];
if (processed) parts.push(`${processed} upscaled`);
if (skipped)   parts.push(`${skipped} skipped`);
if (failed)    parts.push(`${failed} failed`);
if (parts.length) console.log(`\nDone: ${parts.join(", ")}.`);
