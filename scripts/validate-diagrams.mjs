import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { DOMParser } from "@xmldom/xmldom";

const root = resolve(import.meta.dirname, "..");
const specImages = join(root, "spec", "images");
const docsImages = join(root, "docs", "modules", "ROOT", "images");
const diagrams = join(root, "spec", "diagrams");
const failures = [];
const diagramNames = [
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

function fail(path, message) {
  failures.push(`${path}: ${message}`);
}

function validateSvg(path, mode) {
  const svg = readFileSync(path, "utf8");
  const errors = [];
  const document = new DOMParser({
    onError: (level, message) => {
      if (level !== "warning") errors.push(message);
    },
  }).parseFromString(svg, "image/svg+xml");
  const element = document.documentElement;

  if (errors.length) fail(path, `XML parse errors: ${errors.join("; ")}`);
  if (element.localName !== "svg" || element.namespaceURI !== "http://www.w3.org/2000/svg") {
    fail(path, "root must use the SVG namespace");
  }
  if (!element.getAttribute("viewBox")) fail(path, "missing viewBox");
  if (element.getAttribute("preserveAspectRatio") !== "xMidYMid meet") {
    fail(path, "preserveAspectRatio must be xMidYMid meet");
  }
  if (element.getAttribute("role") !== "img") fail(path, "role must be img");
  if (!element.getElementsByTagName("title")[0]?.textContent?.trim()) fail(path, "missing title");
  if (!element.getElementsByTagName("desc")[0]?.textContent?.trim()) fail(path, "missing description");
  if (/<(?:foreignObject|script|iframe|object|embed|image|audio|video)\b/i.test(svg)) {
    fail(path, "contains active or external-capable content");
  }
  if (/\son[a-z]+\s*=|(?:href|src)\s*=\s*["'](?!#|data:)/i.test(svg)) {
    fail(path, "contains an event handler or external resource");
  }
  if (/var\([^,)]*\)/.test(svg)) fail(path, "contains a CSS variable without a concrete fallback");
  if (!svg.includes("var(--themed-svg-diagram-")) fail(path, "missing semantic theme variables");
  if (mode === "adaptive" && !svg.includes("prefers-color-scheme:dark")) {
    fail(path, "missing bundled dark-mode preset");
  }
  if (mode === "host" && svg.includes("prefers-color-scheme:dark")) {
    fail(path, "host output contains adaptive media rules");
  }
}

for (const name of diagramNames) {
  const source = readFileSync(join(diagrams, `${name}.mmd`), "utf8");
  const manifest = JSON.parse(readFileSync(join(diagrams, `${name}.theme.json`), "utf8"));
  if (!source.includes("accTitle:") || !source.includes("accDescr:")) {
    fail(name, "Mermaid source must declare accTitle and accDescr");
  }
  if (manifest.schemaVersion !== 1 || manifest.source?.uri !== `${name}.mmd`) {
    fail(name, "manifest source provenance is incorrect");
  }
  if (!manifest.tokens?.length || !manifest.bindings?.length) {
    fail(name, "manifest lacks semantic tokens or explicit bindings");
  }

  const adaptive = join(specImages, `${name}.svg`);
  const host = join(specImages, `${name}.host.svg`);
  validateSvg(adaptive, "adaptive");
  validateSvg(host, "host");

  for (const suffix of [".svg", ".host.svg"]) {
    const spec = readFileSync(join(specImages, `${name}${suffix}`));
    const docs = readFileSync(join(docsImages, `${name}${suffix}`));
    if (!spec.equals(docs)) fail(name, `${suffix} differs between spec and docs`);
  }

  const fixed = readFileSync(join(specImages, "fixed", `${name}.svg`));
  const original = execFileSync("git", ["show", `HEAD:spec/images/${name}.svg`], { cwd: root });
  if (!fixed.equals(original)) fail(name, "fixed original differs from HEAD provenance");
}

const config = JSON.parse(readFileSync(join(diagrams, "mermaid-config.json"), "utf8"));
if (config.htmlLabels !== false || config.flowchart?.htmlLabels !== false) {
  fail("mermaid-config.json", "htmlLabels must be false globally and for flowcharts");
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("Validated 24 generated SVGs, 24 synced copies, and 12 fixed originals.");
