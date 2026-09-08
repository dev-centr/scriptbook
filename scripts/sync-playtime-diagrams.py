#!/usr/bin/env python3
"""Sync and validate Scriptbook's canonical PlayTime diagram deliveries.

The editable Mermaid sources and Themed SVG manifests remain canonical in
dev-centr/general-knowledge. Scriptbook intentionally vendors only the three
delivery SVGs from the exact commit pinned below.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SOURCE_REPOSITORY = "https://github.com/dev-centr/general-knowledge"
SOURCE_COMMIT = "137492ea980910d1286663654948bd82d2d5ac4b"
SOURCE_DIRECTORY = "docs/modules/ROOT/images"
TARGET_DIRECTORIES = (
    "spec/images",
    "docs/modules/ROOT/images",
)
EXPECTED_SHA256 = {
    "playtime-bind-flow.svg": "7f407c530a432571512a2b0e6d91b96d9d3ac6a1403c88cf7b7a5f1ede3bda47",
    "playtime-bind-flow.host.svg": "2a96d8cc89094aaac4000eac0bd8185b73f2c57148d0f9da6b820eca27760a1a",
    "playtime-bind-flow.fixed.svg": "5875f1c267be56d1eacccedef40779404402131fcdcab38dbe6e8c28757f1cf5",
    "playtime-bootstrap.svg": "feb1d8f65bd3c829600b1213e0dd77df5d75b2d06f4131a13c7696aa7eede095",
    "playtime-bootstrap.host.svg": "be30965e7d1f68b72cbbd30baa3cb978f48d869f219918d207aee59150db9913",
    "playtime-bootstrap.fixed.svg": "3552e31a74f8eb90f5a63ac3656e25df5f8f8053905d7625f72a1a1d7628d7cd",
    "playtime-growth-ratchet.svg": "186b47f058a4887a4e4a941c3f77e5d58c16d63f723d9b3f0ac15c6b483c29d8",
    "playtime-growth-ratchet.host.svg": "037571eeec192fab4fd8ed51a086e8986177f051393a1726062fe03b84585617",
    "playtime-growth-ratchet.fixed.svg": "43a802dbb15f5f71f8e58cca046f80a5e6a48707f43bba0c54a086dc791510d2",
    "playtime-layers.svg": "d0d2783f1e4f98bb71431ed9d591e67724985f401437f34d317653aac686527e",
    "playtime-layers.host.svg": "a8e863a9a2b89d28ee6f05017f3fd2fc2f283fa28f42bdfb08e9d64979cf4f73",
    "playtime-layers.fixed.svg": "cae98c1790fcfeae8eea418b29403a92273e431b3098fa5ef43a4390ac5873b4",
    "playtime-sibling-home.svg": "bc6c8884ccbafca421f2dc827015d7854a762c6d8cbc0f7d4fcb63def859af8b",
    "playtime-sibling-home.host.svg": "475e34ce6fd625c2f1686330045dd973c3d08a17a37ffc53ce58ba0b0855c184",
    "playtime-sibling-home.fixed.svg": "21b5c0a2bf457a1967b1b9734f505c34b303edc07a5fc899203386547f4b7ceb",
    "playtime-overlays.svg": "c702369a5eff0a9a95b41ffd549cc22cffd150eb6ad37f79ee5bc057f004a889",
    "playtime-overlays.host.svg": "15723f8c7c832e1b8eae33aeab47054179aaf493d7e08ab8d9f69f7106e2df46",
    "playtime-overlays.fixed.svg": "9ad77beea886c48690978dfe6d8aecedc2713788cc66d34c096d0d28c2f421e3",
    "playtime-venn.svg": "2b48bf2f387665a4167830ec75d821c4b68a3ad632cbe8a9553d4e9d65ebf299",
    "playtime-venn.host.svg": "ea28d140745533ca036491967fd196ee5cd84ddda3b464565ef27cc7d04c1377",
    "playtime-venn.fixed.svg": "99a8221118776f932f96e1ca5c708e5b0c4aaff2c9dd16857b0273505152cdf1",
    "playtime-facets-not-lattice.svg": "eaac7e99c15a3d55438f95bcb7c97013a394f375f07f547d8d6095ddecfaf400",
    "playtime-facets-not-lattice.host.svg": "229f9e6cd3586b0661acb2321e7771e7c876510c743ef28ca6b0ebffd7772735",
    "playtime-facets-not-lattice.fixed.svg": "7578d2b6cdc99c267884575d83ac8792415f4b1c14074db480e33f44d1866b05",
    "playtime-attic-basement.svg": "13fd62167ec5e56b79e3440620de7a7eb8b22cb05b652a276379fc71a7497a2a",
    "playtime-attic-basement.host.svg": "6166d529b82291f03b5ad4c2778ba145b3d0e68ac8aad701152eb676ca1ea301",
    "playtime-attic-basement.fixed.svg": "3f2e7317994416918d4389a94001d1dbbe573ea3b0eb088944a38bf74880f5d1",
    "playtime-argv.svg": "0d0b362774511d6d2b54782b6d7a1bf557a1892897639edd945df3107f4b087c",
    "playtime-argv.host.svg": "113bc4e67aee6eb9ab1388593186b6457b450eb6537892248b11624d4450e0b9",
    "playtime-argv.fixed.svg": "1d84c53a397664b666945e6b64fe18193bef965961ae99ef4adcdf80db6f38cf",
}
CANONICAL_NAMES = {filename.split(".", 1)[0] for filename in EXPECTED_SHA256}
DISALLOWED_ELEMENTS = {
    "animate",
    "animateMotion",
    "animateTransform",
    "audio",
    "embed",
    "foreignObject",
    "iframe",
    "image",
    "object",
    "script",
    "set",
    "video",
}
MOJIBAKE_MARKERS = ("â€", "Ã", "Â", "\ufffd")
ROOT = Path(__file__).resolve().parents[1]


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_bytes(source: Path, filename: str) -> bytes:
    git_path = f"{SOURCE_DIRECTORY}/{filename}"
    probe = subprocess.run(
        ["git", "-C", str(source), "cat-file", "-e", f"{SOURCE_COMMIT}^{{commit}}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if probe.returncode == 0:
        result = subprocess.run(
            ["git", "-C", str(source), "show", f"{SOURCE_COMMIT}:{git_path}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.decode("utf-8", errors="replace").strip())
        return result.stdout

    checkout_file = source / SOURCE_DIRECTORY / filename
    if not checkout_file.is_file():
        raise RuntimeError(
            f"{source} has neither commit {SOURCE_COMMIT} nor {checkout_file}"
        )
    return checkout_file.read_bytes()


def sync(source: Path) -> None:
    for filename, expected in EXPECTED_SHA256.items():
        data = source_bytes(source, filename)
        actual = digest(data)
        if actual != expected:
            raise RuntimeError(
                f"canonical hash mismatch for {filename}: expected {expected}, got {actual}"
            )
        for directory in TARGET_DIRECTORIES:
            target = ROOT / directory / filename
            target.write_bytes(data)
    print(
        f"Synced 30 canonical deliveries from {SOURCE_REPOSITORY}@{SOURCE_COMMIT} "
        "to both public image directories."
    )


def local_name(element: ET.Element | str) -> str:
    tag = element.tag if isinstance(element, ET.Element) else element
    return tag.rsplit("}", 1)[-1]


def validate_svg(path: Path, filename: str, failures: list[str]) -> None:
    data = path.read_bytes()
    expected = EXPECTED_SHA256[filename]
    if digest(data) != expected:
        failures.append(f"{path.relative_to(ROOT)}: stale or noncanonical content")
        return

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        failures.append(f"{path.relative_to(ROOT)}: not UTF-8: {error}")
        return
    if any(marker in text for marker in MOJIBAKE_MARKERS):
        failures.append(f"{path.relative_to(ROOT)}: possible encoding corruption")

    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        failures.append(f"{path.relative_to(ROOT)}: invalid XML: {error}")
        return

    if root.tag != "{http://www.w3.org/2000/svg}svg":
        failures.append(f"{path.relative_to(ROOT)}: root is not namespaced SVG")
    for attribute in ("viewBox", "role"):
        if not root.get(attribute):
            failures.append(f"{path.relative_to(ROOT)}: missing {attribute}")
    if root.get("role") != "img":
        failures.append(f"{path.relative_to(ROOT)}: role must be img")

    children = list(root)
    title = next((item for item in children if local_name(item) == "title"), None)
    desc = next((item for item in children if local_name(item) == "desc"), None)
    if title is None or not "".join(title.itertext()).strip():
        failures.append(f"{path.relative_to(ROOT)}: missing accessible title")
    if desc is None or not "".join(desc.itertext()).strip():
        failures.append(f"{path.relative_to(ROOT)}: missing accessible description")

    for element in root.iter():
        name = local_name(element)
        if name in DISALLOWED_ELEMENTS:
            failures.append(f"{path.relative_to(ROOT)}: unsafe <{name}> element")
        for attribute, value in element.attrib.items():
            attr_name = local_name(attribute).lower()
            lowered = value.strip().lower()
            if attr_name.startswith("on"):
                failures.append(
                    f"{path.relative_to(ROOT)}: event attribute {attr_name}"
                )
            if attr_name in {"href", "src"} and lowered and not lowered.startswith("#"):
                failures.append(
                    f"{path.relative_to(ROOT)}: external resource in {attr_name}"
                )

    if re.search(r"@import|url\(\s*['\"]?(?:https?:|//|data:)", text, re.IGNORECASE):
        failures.append(f"{path.relative_to(ROOT)}: external CSS resource")
    if re.search(r"var\(\s*--[^,)]+\)", text):
        failures.append(f"{path.relative_to(ROOT)}: CSS variable lacks fallback")

    if filename.endswith(".host.svg"):
        if "var(--themed-svg-" not in text:
            failures.append(f"{path.relative_to(ROOT)}: host mode lacks theme variables")
        if "prefers-color-scheme" in text:
            failures.append(f"{path.relative_to(ROOT)}: host mode embeds mode selection")
    elif filename.endswith(".fixed.svg"):
        if "var(--" in text or "prefers-color-scheme" in text:
            failures.append(f"{path.relative_to(ROOT)}: fixed mode is not concrete")
    else:
        if "prefers-color-scheme:dark" not in text.replace(" ", ""):
            failures.append(f"{path.relative_to(ROOT)}: adaptive mode lacks dark preset")


def validate_imageblocks(failures: list[str]) -> None:
    pages = ROOT / "docs" / "modules" / "ROOT" / "pages"
    for page in pages.rglob("*.adoc"):
        try:
            text = page.read_text(encoding="utf-8")
        except UnicodeDecodeError as error:
            failures.append(f"{page.relative_to(ROOT)}: not UTF-8: {error}")
            continue
        if any(marker in text for marker in MOJIBAKE_MARKERS):
            failures.append(f"{page.relative_to(ROOT)}: possible encoding corruption")
        lines = text.splitlines()
        for index, line in enumerate(lines):
            match = re.match(r"^image::(?:images/)?(playtime-[^.[]+)\.svg\[", line)
            if not match:
                continue
            previous = lines[index - 1].strip() if index else ""
            has_role = previous == "[.themed-svg]"
            if match.group(1) in CANONICAL_NAMES and not has_role:
                failures.append(
                    f"{page.relative_to(ROOT)}:{index + 1}: canonical diagram lacks themed-svg role"
                )
            if match.group(1) in {"playtime-wrong-translator", "playtime-two-doors"} and has_role:
                failures.append(
                    f"{page.relative_to(ROOT)}:{index + 1}: noncanonical diagram must remain unmarked"
                )


def check() -> None:
    failures: list[str] = []
    for directory in TARGET_DIRECTORIES:
        target_dir = ROOT / directory
        for filename in EXPECTED_SHA256:
            path = target_dir / filename
            if not path.is_file():
                failures.append(f"{path.relative_to(ROOT)}: missing")
            else:
                validate_svg(path, filename, failures)
        for pattern in ("playtime-*.mmd", "playtime-*.theme.json", "playtime-*.manifest.*"):
            for duplicate in target_dir.glob(pattern):
                failures.append(
                    f"{duplicate.relative_to(ROOT)}: canonical source/manifest must not be duplicated"
                )

    validate_imageblocks(failures)
    if failures:
        raise RuntimeError("\n".join(failures))
    print(
        "Checked 60 pinned SVG copies: freshness, XML, accessibility, safety, "
        "delivery modes, UTF-8, and Antora roles passed."
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Check vendored PlayTime diagrams, or sync them from an exact local "
            "general-knowledge checkout/commit without network access."
        )
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check",
        action="store_true",
        help="validate committed deliveries without reading the source repository (default)",
    )
    mode.add_argument(
        "--sync",
        action="store_true",
        help="copy the pinned canonical deliveries before checking",
    )
    parser.add_argument(
        "--source",
        type=Path,
        help=(
            "local general-knowledge git repository containing the pinned commit, "
            "or an exact exported checkout"
        ),
    )
    args = parser.parse_args()

    try:
        if args.sync:
            if args.source is None:
                parser.error("--sync requires --source")
            sync(args.source.resolve())
        elif args.source is not None:
            parser.error("--source is only valid with --sync")
        check()
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
