import Foundation
import Testing

@testable import SwaTex

/// Differential layout tests against RaTeX and KaTeX on the AI Markdown math corpus.
///
/// `Resources/differential/ai_markdown_corpus.jsonl` holds 1,665 formulas (real
/// AI Markdown Web documents, the KaTeX command vocabulary, Swift fixture fuzz,
/// typical AI answers, CJK text, environments, macros, streaming prefixes,
/// deep nesting, and long formulas) with:
///
/// - `ratex`: the RaTeX v0.1.15 (`5f7dc48`) display list, item by item
///   (glyph/rule/rect positions, path command counts and bounds), or its error.
/// - `katex`: KaTeX 0.16.47 status and its rendered `.katex-html` width in em
///   (headless Chromium, 20px), when KaTeX renders the formula.
///
/// SwaTex must reproduce RaTeX's geometry within 2e-4 em for every formula,
/// except entries with a documented `deviation` (places where SwaTex follows
/// KaTeX instead of RaTeX). SwaTex widths must also stay within ±5% of KaTeX
/// for non-fuzz formulas, except entries flagged `katexOutlier`.
///
/// The `deep` group (hundreds of nested levels) is excluded: whether it lays out
/// depends on the stack-headroom guard, i.e. on the build configuration and the
/// calling thread's stack size. `StackGuardTests` covers that behavior.
///
/// Regenerate with `scripts/differential/generate_fixture.py` (see its
/// docstring for the reference tools and versions). No network is needed to run
/// these tests.
@Suite("DifferentialLayout")
struct DifferentialLayoutTests {
    private static let tolerance = 2e-4

    private struct Entry {
        var id: String
        var tex: String
        var inline: Bool
        var group: String
        var ratex: [String: Any]
        var katexWidth: Double?
        var deviation: String?
        var katexOutlier: Bool
    }

    private static func entries() throws -> [Entry] {
        let url = try #require(
            Bundle.module.url(
                forResource: "ai_markdown_corpus", withExtension: "jsonl",
                subdirectory: "differential"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            let obj = try #require(
                try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            let katex = obj["katex"] as? [String: Any]
            return Entry(
                id: obj["id"] as? String ?? "",
                tex: obj["tex"] as? String ?? "",
                inline: (obj["mode"] as? String) == "inline",
                group: obj["group"] as? String ?? "",
                ratex: obj["ratex"] as? [String: Any] ?? [:],
                katexWidth: (katex?["w"] as? NSNumber)?.doubleValue,
                deviation: obj["deviation"] as? String,
                katexOutlier: obj["katexOutlier"] as? Bool ?? false)
        }
    }

    private static func render(_ entry: Entry) -> DisplayList? {
        try? SwaTexEngine.displayList(for: entry.tex, style: entry.inline ? .text : .display)
    }

    /// Encode a display item exactly like `generate_fixture.py`.
    private static func encode(_ item: DisplayItem) -> [Any] {
        func colorSuffix(_ c: Color) -> [Any] {
            c.r == 0 && c.g == 0 && c.b == 0 && c.a == 1
                ? [] : [[Double(c.r), Double(c.g), Double(c.b), Double(c.a)]]
        }
        switch item {
        case let .glyphPath(x, y, scale, font, charCode, color):
            return ["G", x, y, scale, font, Int(charCode)] + colorSuffix(color)
        case let .line(x, y, width, thickness, color, _):
            return ["L", x, y, width, thickness] + colorSuffix(color)
        case let .rect(x, y, width, height, color):
            return ["R", x, y, width, height] + colorSuffix(color)
        case let .path(x, y, commands, _, color):
            var xs: [Double] = []
            var ys: [Double] = []
            for command in commands {
                switch command {
                case let .moveTo(px, py), let .lineTo(px, py):
                    xs.append(px)
                    ys.append(py)
                case let .cubicTo(x1, y1, x2, y2, px, py):
                    xs += [x1, x2, px]
                    ys += [y1, y2, py]
                case let .quadTo(x1, y1, px, py):
                    xs += [x1, px]
                    ys += [y1, py]
                case .close:
                    break
                }
            }
            return [
                "P", x, y, commands.count, xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0,
                ys.max() ?? 0,
            ] + colorSuffix(color)
        }
    }

    private static func close(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (x as String, y as String):
            return x == y
        case let (x as [Any], y as [Any]):
            return x.count == y.count && zip(x, y).allSatisfy { close($0, $1) }
        default:
            guard let x = (a as? NSNumber)?.doubleValue ?? (a as? Double),
                let y = (b as? NSNumber)?.doubleValue ?? (b as? Double)
            else { return false }
            return abs(x - y) <= tolerance
        }
    }

    /// Returns nil when SwaTex matches the RaTeX reference, else a description.
    private static func mismatch(_ entry: Entry, _ dl: DisplayList?) -> String? {
        if entry.ratex["error"] as? Bool == true {
            return dl == nil ? nil : "SwaTex accepted, RaTeX rejected"
        }
        guard let dl else { return "SwaTex rejected, RaTeX accepted" }
        let ref = entry.ratex
        for (key, value) in [("w", dl.width), ("h", dl.height), ("d", dl.depth)] {
            let expected = (ref[key] as? NSNumber)?.doubleValue ?? .nan
            if !(abs(expected - value) <= tolerance) {
                return "\(key) swatex \(value) ratex \(expected)"
            }
        }
        let count = (ref["n"] as? NSNumber)?.intValue ?? -1
        if dl.items.count != count {
            return "item count swatex \(dl.items.count) ratex \(count)"
        }
        let items = ref["items"] as? [[Any]] ?? []
        for (index, expected) in items.enumerated() {
            let actual = encode(dl.items[index])
            if !close(actual, expected) {
                return "item \(index) swatex \(actual) ratex \(expected)"
            }
        }
        return nil
    }

    @Test func matchesRaTeXGeometry() throws {
        let entries = try Self.entries()
        #expect(entries.count > 1600)
        var failures: [String] = []
        var compared = 0
        for entry in entries where entry.deviation == nil && entry.group != "deep" {
            compared += 1
            if let problem = Self.mismatch(entry, Self.render(entry)) {
                failures.append("\(entry.id) \(entry.tex.prefix(60).debugDescription): \(problem)")
            }
        }
        #expect(compared > 1590)
        #expect(
            failures.isEmpty,
            Comment(
                rawValue: "\(failures.count)/\(compared) RaTeX differences:\n"
                    + failures.prefix(20).joined(separator: "\n")))
    }

    @Test func widthsAgreeWithKaTeX() throws {
        var failures: [String] = []
        var agreeing = 0
        var measured = 0
        for entry in try Self.entries() where entry.group != "fixture-fuzz" && entry.group != "deep"
        {
            guard let katexWidth = entry.katexWidth, let dl = Self.render(entry) else { continue }
            measured += 1
            let withinFivePercent = abs(dl.width / katexWidth - 1) <= 0.05
            if withinFivePercent {
                agreeing += 1
            } else if !entry.katexOutlier {
                failures.append(
                    "\(entry.id) \(entry.tex.prefix(60).debugDescription): "
                        + "swatex \(dl.width)em katex \(katexWidth)em")
            }
        }
        #expect(measured > 400)
        #expect(
            failures.isEmpty,
            Comment(
                rawValue: "\(failures.count) new KaTeX width outliers "
                    + "(\(agreeing)/\(measured) within 5%):\n"
                    + failures.prefix(20).joined(separator: "\n")))
    }

    private static let overMarks = [
        #"\widetilde"#, #"\overrightarrow"#, #"\overleftarrow"#, #"\Overrightarrow"#,
        #"\overleftrightarrow"#, #"\overgroup"#, #"\overlinesegment"#, #"\overleftharpoon"#,
    ].map { "{\($0){x}}" }.joined(separator: #" \quad "#)

    private static let underMarks = [
        #"\underleftarrow"#, #"\underrightarrow"#, #"\underleftrightarrow"#, #"\undergroup"#,
        #"\underlinesegment"#, #"\utilde"#, #"\xleftarrow"#, #"\xrightarrow"#,
    ].map { "{\($0){x}}" }.joined(separator: #" \quad "#)

    private static let regressionCases: [(String, Double)] = [
        (#"\begin{aligned} a &= b & c &= d \\ e &= f & g &= h \end{aligned}"#, 117.640625),
        (#"\begin{alignedat}{2} a &= b & c &= d \end{alignedat}"#, 91.578125),
        (#"\begin{aligned} f(x) &= (x+1)^2 \\ &= x^2+2x+1 \end{aligned}"#, 165.40625),
        (#"\begin{split} a &= b \\ &= c \end{split}"#, 45.921875),
        (overMarks, 275.703125),
        (underMarks, 298.953125),
    ]

    /// The multi-column alignment and stretchy-mark regressions that motivated
    /// this suite, pinned against KaTeX's rendered widths (20px).
    @Test(arguments: regressionCases)
    func silentMisLayoutRegressions(_ tex: String, _ katexPx: Double) throws {
        let dl = try SwaTexEngine.displayList(for: tex, style: .display)
        #expect(
            abs(dl.width * 20 / katexPx - 1) <= 0.01, "\(dl.width * 20)px vs KaTeX \(katexPx)px")
    }
}
