import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, relative, resolve } from "node:path";

export const diagramNames = [
  "playtime-argv",
  "playtime-attic-basement",
  "playtime-bind-flow",
  "playtime-bootstrap",
  "playtime-facets-not-lattice",
  "playtime-growth-ratchet",
  "playtime-layers",
  "playtime-overlays",
  "playtime-sibling-home",
  "playtime-two-doors",
  "playtime-venn",
  "playtime-wrong-translator",
];

const check = process.argv.includes("--check");
const root = resolve(import.meta.dirname, "..");
const diagrams = join(root, "spec", "diagrams");
const specImages = join(root, "spec", "images");
const docsImages = join(root, "docs", "modules", "ROOT", "images");
const pnpm = process.platform === "win32" ? "pnpm.cmd" : "pnpm";
const temporary = mkdtempSync(join(tmpdir(), "scriptbook-diagrams-"));
const stylesheetTokens = [
  [".themed-svg-root", "background-color", "#f3f1ec"],
  [".themed-svg-root text", "fill", "#1a1a1a"],
  [".themed-svg-root .label-container", "fill", "#ffffff"],
  [".themed-svg-root .label-container", "stroke", "#2c2c2c"],
  [".themed-svg-root .cluster rect", "fill", "#e8f0ea"],
  [".themed-svg-root .cluster rect", "stroke", "#2c2c2c"],
  [".themed-svg-root .flowchart-link", "stroke", "#2c2c2c"],
  [".themed-svg-root marker path", "fill", "#2c2c2c"],
  [".themed-svg-root marker path", "stroke", "#2c2c2c"],
];

function run(args) {
  const result = spawnSync(pnpm, args, {
    cwd: root,
    encoding: "utf8",
    shell: process.platform === "win32",
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function sync(source, target) {
  if (check) {
    if (!existsSync(target) || !readFileSync(source).equals(readFileSync(target))) {
      console.error(`stale: ${relative(root, target)}`);
      process.exitCode = 3;
    }
    return;
  }
  copyFileSync(source, target);
}

try {
  for (const name of diagramNames) {
    const raw = join(temporary, `${name}.raw.svg`);
    const adaptive = join(specImages, `${name}.svg`);
    const host = join(specImages, `${name}.host.svg`);

    run([
      "exec",
      "mmdc",
      "--input",
      join(diagrams, `${name}.mmd`),
      "--output",
      raw,
      "--configFile",
      join(diagrams, "mermaid-config.json"),
      "--backgroundColor",
      "transparent",
      "--quiet",
    ]);

    const rendered = readFileSync(raw, "utf8")
      .replace(/^<\?xml[^>]*>\s*/i, "")
      .replace(/\srole="[^"]*"/i, ' role="img"')
      .replace(
        /<svg\b([^>]*)\sclass="([^"]*)"([^>]*)>/i,
        '<svg$1 class="$2 themed-svg-root"$3 preserveAspectRatio="xMidYMid meet">',
      )
      .replace(
        /<\/style>/i,
        `</style><style id="themed-svg-bindings">${stylesheetTokens
          .map(([selector, property, value]) => `${selector}{${property}:${value} !important}`)
          .join("")}</style>`,
      );
    writeFileSync(raw, `<?xml version="1.0" encoding="UTF-8"?>\n${rendered}`, "utf8");

    run([
      "exec",
      "mermaid-svg-css-vars",
      "--manifest",
      join(diagrams, `${name}.theme.json`),
      "--dual-output",
      ...(check ? ["--check"] : []),
      "--output",
      adaptive,
      "--host-output",
      host,
      raw,
    ]);

    sync(adaptive, join(docsImages, `${name}.svg`));
    sync(host, join(docsImages, `${name}.host.svg`));
  }
} finally {
  rmSync(temporary, { recursive: true, force: true });
}

if (process.exitCode) process.exit(process.exitCode);
console.log(check ? "All 12 diagram pairs are current." : "Generated and synced 12 diagram pairs.");
