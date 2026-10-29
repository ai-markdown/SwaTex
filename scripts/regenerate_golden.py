#!/usr/bin/env python3
"""Regenerate the golden layout fixtures from the RaTeX reference engine.

The fixtures under Tests/SwaTexTests/Resources/golden/*.jsonl hold RaTeX's
`ratex-layout` output (box + display-list summary, rounded to 5 decimals).
SwaTex must match them exactly, except for the documented `KATEX_OVERRIDES`
below: inputs where SwaTex deliberately follows KaTeX (or KaTeX's error
boundary) instead of a RaTeX behavior. For those, the fixture line is taken
from SwaTex's own `LayoutDump` and tagged with `"override"` so the deviation
stays visible and reviewable.

Reference: RaTeX v0.1.15 (5f7dc48), `cargo build --release -p ratex-layout`.

Usage:
  scripts/regenerate_golden.py <ratex-checkout> <ratex-layout-bin> <LayoutDump-bin>

Corpora:
  test_cases.jsonl / test_case_ce.jsonl / test_cases_prooftree.jsonl
      inputs = RaTeX tests/golden/<name>.txt
  test_cases_coverage.jsonl
      inputs = the existing fixture's inputs (SwaTex coverage corpus)
"""

import json
import os
import subprocess
import sys

# input -> reason. Keep in sync with GoldenLayoutTests / CoverageGoldenTests docs.
KATEX_OVERRIDES = {
    # SwaTex raises the \vcenter ink onto the math axis (KaTeX moves the box);
    # RaTeX only rewrites height/depth and leaves the ink on the baseline.
    "a\\vcenter{\\frac{a}{b}}b": "vcenter ink is axis-centered (KaTeX)",
    "a\\vcenter{\\hbox{$\\frac{p}{q}$}}b": "vcenter ink is axis-centered (KaTeX)",
    # KaTeX rejects an unterminated \verb and \limits after a non-operator.
    "\\verb|abc": "KaTeX error boundary",
    "\\verb*|a b": "KaTeX error boundary",
    "x\\limits^2": "KaTeX error boundary",
    # U+25CB is not a KaTeX symbol; RaTeX 0.1.15 adds a private alias that
    # renders it as a scaled U+25EF. SwaTex keeps KaTeX's plain-glyph handling.
    "○\\div□=5\\quad□\\div○=5": "RaTeX-only U+25CB alias not adopted",
}

GOLDEN = os.path.join(os.path.dirname(__file__), "..", "Tests", "SwaTexTests", "Resources", "golden")


def run(binary, inputs):
    proc = subprocess.run([binary], input="\n".join(inputs) + "\n", capture_output=True,
                          text=True, check=True)
    out = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    if len(out) != len(inputs):
        sys.exit(f"{binary}: expected {len(inputs)} results, got {len(out)}")
    return out


def summary(result):
    if result.get("error"):
        return {"error": True, "input": result["input"]}
    return {"box": result["box"], "displayList": result["displayList"], "input": result["input"]}


def regenerate(name, inputs, ratex_bin, swift_bin):
    rust = run(ratex_bin, inputs)
    swift = run(swift_bin, inputs)
    lines, unexplained = [], []
    for r, s in zip(rust, swift):
        r, s = summary(r), summary(s)
        if r.get("error") != s.get("error") or r.get("displayList") != s.get("displayList"):
            reason = KATEX_OVERRIDES.get(r["input"])
            if reason is None:
                unexplained.append(r["input"])
            else:
                r = dict(s, override=reason)
        lines.append(json.dumps(r, sort_keys=True, ensure_ascii=False, separators=(",", ":")))
    with open(os.path.join(GOLDEN, name + ".jsonl"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{name}: {len(lines)} fixtures, {len(unexplained)} unexplained differences")
    for item in unexplained:
        print("  UNEXPLAINED:", item)
    return not unexplained


def main():
    ratex_root, ratex_bin, swift_bin = sys.argv[1:4]
    ok = True
    for name in ("test_cases", "test_case_ce", "test_cases_prooftree"):
        with open(os.path.join(ratex_root, "tests", "golden", name + ".txt")) as f:
            inputs = [line.strip() for line in f if line.strip()]
        ok &= regenerate(name, inputs, ratex_bin, swift_bin)
    with open(os.path.join(GOLDEN, "test_cases_coverage.jsonl")) as f:
        inputs = [json.loads(line)["input"] for line in f if line.strip()]
    ok &= regenerate("test_cases_coverage", inputs, ratex_bin, swift_bin)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
