#!/usr/bin/env python3
"""Generate the SwaTex-vs-RaTeX/KaTeX differential fixture.

Output: Tests/SwaTexTests/Resources/differential/ai_markdown_corpus.jsonl,
consumed offline by Tests/SwaTexTests/Layout/DifferentialLayoutTests.swift.

Inputs (all produced outside this repository; nothing here needs network):

  corpus.jsonl        AI Markdown math corpus: one {"id","tex","mode","group"}
                      per line. 1,665 formulas extracted from the AI Markdown
                      Web corpus (real documents, KaTeX vocabulary, Swift
                      fixture fuzz) plus authored stress inputs (typical AI
                      answers, CJK, environments, macros, streaming prefixes,
                      deep nesting, long formulas).
  ratex.jsonl         Output of `ratex_dl_dump.rs` (RaTeX v0.1.15, commit
                      5f7dc48) over corpus.jsonl: full serialized display lists.
  katex-results.json  Output of `katex-ref.mjs` (KaTeX 0.16.47, the version the
                      AI Markdown Web build resolves): per-formula status.
  katex-metrics.json  Output of `katex-browser.mjs` (headless Chromium, 20px):
                      rendered `.katex-html` width per formula.
  swatex.jsonl        SwaTex's own dump (same format as ratex.jsonl), used only
                      to compute which formulas are documented deviations.

Fixture line format (compact, rounded to 1e-4 em):

  {"id","tex","mode","group",
   "ratex": {"w","h","d","n","items":[...]} | {"error": true},
                                      # n = total item count; items holds at
                                      # most MAX_ITEMS leading items
   "katex": {"ok": bool, "w": em-width or null},
   "deviation": "<reason>"            # only for documented deviations
   "katexOutlier": true}              # SwaTex width outside +-5% of KaTeX

Items: ["G", x, y, scale, font, codepoint] glyph, ["L", x, y, w, t] rule line,
["R", x, y, w, h] rect, ["P", x, y, n, minX, minY, maxX, maxY] path with its
command count and control-point bounds (relative to x, y).

Usage:
  generate_fixture.py corpus.jsonl ratex.jsonl katex-results.json \\
      katex-metrics.json swatex.jsonl
"""

import json
import os
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "Tests", "SwaTexTests",
                   "Resources", "differential", "ai_markdown_corpus.jsonl")
FONT_PX = 20.0
TOL = 2e-4
# Very long formulas keep their box, item count, and only the first items to
# bound the fixture size; the rest of their geometry is the same code path.
MAX_ITEMS = 64

# Reviewed, intentional SwaTex deviations from RaTeX v0.1.15 (id -> reason).
DEVIATIONS = {
    "w00069": "\\vcenter ink is raised onto the math axis (KaTeX); RaTeX keeps it on the baseline",
    "w00246": "\\vcenter ink is raised onto the math axis (KaTeX); RaTeX keeps it on the baseline",
    "w00768": "text-mode '---' ligature matches KaTeX width; RaTeX lays out three hyphens",
    "w00779": "text-mode '---' ligature matches KaTeX width; RaTeX lays out three hyphens",
    "w00785": "text-mode '---' ligature matches KaTeX width; RaTeX lays out three hyphens",
    "w01010": "text-mode '---' ligature matches KaTeX width; RaTeX lays out three hyphens",
    "w01039": "text-mode '---' ligature matches KaTeX width; RaTeX lays out three hyphens",
    "w01210": "U+FEFF renders as zero-width (KaTeX); RaTeX draws a fallback box",
    "s0143": "SwaTex accepts \\DeclareMathOperator (KaTeX 0.16.47 and RaTeX reject it)",
    "s0423": "SwaTex's recursion limit (512) accepts nesting RaTeX (32) rejects; KaTeX accepts it",
    "s0424": "SwaTex's recursion limit (512) accepts nesting RaTeX (32) rejects; KaTeX accepts it",
    "s0427": "SwaTex's recursion limit (512) accepts nesting RaTeX (32) rejects; KaTeX accepts it",
    "s0430": "SwaTex's recursion limit (512) accepts nesting RaTeX (32) rejects; KaTeX accepts it",
    "s0431": "SwaTex's recursion limit (512) accepts nesting RaTeX (32) rejects; KaTeX accepts it",
    "s0432": "SwaTex's recursion limit (512) accepts nesting RaTeX (32) rejects; KaTeX accepts it",
    "s0435": "SwaTex's recursion limit (512) accepts nesting RaTeX (32) rejects; KaTeX accepts it",
}


def r4(v):
    v = round(v, 4)
    return 0.0 if v == 0 else v


def color_suffix(c):
    if c.get("r", 0) == 0 and c.get("g", 0) == 0 and c.get("b", 0) == 0 and c.get("a", 1) == 1:
        return []
    return [[r4(c["r"]), r4(c["g"]), r4(c["b"]), r4(c["a"])]]


def path_points(commands):
    for c in commands:
        for kx, ky in (("x1", "y1"), ("x2", "y2"), ("x", "y")):
            if kx in c:
                yield c[kx], c[ky]


def encode_item(it):
    t = it["type"]
    if t == "GlyphPath":
        return ["G", r4(it["x"]), r4(it["y"]), r4(it["scale"]), it["font"], it["char_code"]] \
            + color_suffix(it["color"])
    if t == "Line":
        return ["L", r4(it["x"]), r4(it["y"]), r4(it["width"]), r4(it["thickness"])] \
            + color_suffix(it["color"])
    if t == "Rect":
        return ["R", r4(it["x"]), r4(it["y"]), r4(it["width"]), r4(it["height"])] \
            + color_suffix(it["color"])
    pts = list(path_points(it["commands"]))
    xs = [p[0] for p in pts] or [0.0]
    ys = [p[1] for p in pts] or [0.0]
    return ["P", r4(it["x"]), r4(it["y"]), len(it["commands"]),
            r4(min(xs)), r4(min(ys)), r4(max(xs)), r4(max(ys))] + color_suffix(it["color"])


def encode_dl(dl, cap=None):
    items = dl["items"] if cap is None else dl["items"][:cap]
    out = {"w": r4(dl["width"]), "h": r4(dl["height"]), "d": r4(dl["depth"]),
           "n": len(dl["items"]), "items": [encode_item(i) for i in items]}
    return out


def same(a, b):
    if a.keys() != b.keys():
        return False
    if "error" in a:
        return True
    if any(abs(a[k] - b[k]) > TOL for k in ("w", "h", "d")) or a["n"] != b["n"]:
        return False
    for x, y in zip(a["items"], b["items"]):
        if len(x) != len(y):
            return False
        for u, v in zip(x, y):
            if isinstance(u, float) or isinstance(v, float):
                if abs(u - v) > TOL:
                    return False
            elif isinstance(u, list):
                if any(abs(p - q) > TOL for p, q in zip(u, v)):
                    return False
            elif u != v:
                return False
    return True


def load(path):
    return {d["id"]: d for d in map(json.loads, open(path)) if d}


def main():
    corpus_p, ratex_p, kres_p, kmet_p, swatex_p = sys.argv[1:6]
    corpus = [json.loads(l) for l in open(corpus_p) if l.strip()]
    ratex, swatex = load(ratex_p), load(swatex_p)
    kstatus = {r["id"]: r["status"] for r in json.load(open(kres_p))["results"]}
    kwidth = {m["id"]: m["width"] for m in json.load(open(kmet_p))["metrics"]}

    lines, unexplained, outliers = [], [], 0
    for row in corpus:
        i = row["id"]
        r, s = ratex[i], swatex[i]
        ref = encode_dl(r["dl"]) if r["ok"] else {"error": True}
        got = encode_dl(s["dl"]) if s["ok"] else {"error": True}
        k_ok = kstatus.get(i) == "ok"
        k_w = kwidth.get(i)
        entry = {"id": i, "tex": row["tex"], "mode": row["mode"], "group": row["group"],
                 "ratex": ref,
                 "katex": {"ok": k_ok, "w": r4(k_w / FONT_PX) if k_ok and k_w and k_w > 2 else None}}
        if not same(ref, got):
            if i in DEVIATIONS:
                entry["deviation"] = DEVIATIONS[i]
            else:
                unexplained.append(i)
        kw = entry["katex"]["w"]
        if kw and "w" in got and row["group"] != "fixture-fuzz" and abs(got["w"] / kw - 1) > 0.05:
            entry["katexOutlier"] = True
            outliers += 1
        if "items" in ref and len(ref["items"]) > MAX_ITEMS:
            ref["items"] = ref["items"][:MAX_ITEMS]
        lines.append(json.dumps(entry, ensure_ascii=False, separators=(",", ":")))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{len(lines)} fixtures, {outliers} KaTeX width outliers, "
          f"{len(unexplained)} unexplained RaTeX differences")
    for i in unexplained:
        print("  UNEXPLAINED:", i)
    sys.exit(1 if unexplained else 0)


if __name__ == "__main__":
    main()
