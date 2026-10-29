// Accent layout.
// Port of crates/ratex-layout/src/engine.rs (`layout_accent`, RaTeX 0.1.15).

/// `\vec` KaTeX SVG: nudge slightly right to match KaTeX reference.
private let vecSkewExtraRightEm = 0.018

/// Extract the italic correction only when this box itself is a glyph.
///
/// This distinction mirrors KaTeX's `base instanceof SymbolNode` check. Recursing through an
/// `hbox` would incorrectly treat text/group spans as symbols and pull their subscripts left.
func directGlyphItalic(_ lb: LayoutBox) -> Double? {
    if case let .glyph(fontId, charCode) = lb.content {
        return fontId.metrics(forChar: charCode)?.italic
    }
    return nil
}

/// Find the first glyph inside a box.
///
/// KaTeX special-cases `\oiint` and `\oiiint`: their overlay makes the base a span rather than
/// a `SymbolNode`, but the underlying integral glyph's italic correction still applies.
func firstGlyphItalic(_ lb: LayoutBox) -> Double? {
    switch lb.content {
    case .glyph:
        return directGlyphItalic(lb)
    case let .hbox(children):
        for child in children {
            if let italic = firstGlyphItalic(child) {
                return italic
            }
        }
        return nil
    default:
        return nil
    }
}

/// KaTeX `groupLength` for wide SVG accents: `ordgroup.body.length`, else 1.
func accentOrdgroupLen(_ base: ParseNode) -> Int {
    if case let .ordGroup(body, _) = base.kind {
        return max(body.count, 1)
    }
    return 1
}

/// Extract the skew (italic correction) of the innermost/last glyph in a box.
/// Used by shifty accents (\hat, \tilde…) to horizontally centre the mark
/// over italic math letters (e.g. M in MathItalic has skew ≈ 0.083em).
func glyphSkew(_ lb: LayoutBox) -> Double {
    switch lb.content {
    case let .glyph(fontId, charCode):
        fontId.metrics(forChar: charCode)?.skew ?? 0
    case let .hbox(children):
        children.last.map(glyphSkew) ?? 0
    default:
        0
    }
}

/// Vertical placement of a stretchy accent, brace, or arrow relative to its base.
enum StretchyPlacement {
    case above
    case below
}

/// Shared clearance model for stretchy paths (`\widehat`, `\overrightarrow`,
/// `\overbrace`, …).
struct StretchySpec {
    var placement: StretchyPlacement
    var gap: Double

    static func accent(_ label: String, isBelow: Bool, _ options: LayoutOptions) -> StretchySpec {
        // KaTeX accentunder.ts assigns only \utilde a 0.12em kern.
        StretchySpec(
            placement: isBelow ? .below : .above,
            gap: label == "\\utilde" ? 3.0 * options.metrics.defaultRuleThickness : 0.0)
    }

    static func horizontalBrace(isOver: Bool, _ options: LayoutOptions) -> StretchySpec {
        // KaTeX's 0.1em brace kern is 2.5 default rule units.
        StretchySpec(
            placement: isOver ? .above : .below,
            gap: 2.5 * options.metrics.defaultRuleThickness)
    }
}

/// Center `body` in `width` when the stretchy mark is wider than its base
/// (KaTeX stretchy `minWidth`).
func paddedToWidth(_ body: LayoutBox, _ width: Double) -> LayoutBox {
    if width <= body.width + Double.ulpOfOne {
        return body
    }
    let pad = (width - body.width) / 2.0
    return makeHBox([.kern(pad), body, .kern(pad)])
}

/// Place a top-origin stretchy path (height 0, depth = path height) above or
/// below its base.
func composeStretchy(
    _ base: LayoutBox, _ accent: LayoutBox, _ spec: StretchySpec, skew: Double, color: Color
) -> LayoutBox {
    let isBelow = spec.placement == .below
    let clearance = isBelow ? base.height + base.depth + spec.gap : base.height + spec.gap
    let (height, depth) =
        isBelow
        ? (base.height, base.depth + spec.gap + accent.depth)
        : (base.height + spec.gap + accent.depth, base.depth)
    return LayoutBox(
        width: base.width, height: height, depth: depth,
        content: .accent(
            base: base, accent: accent, clearance: clearance, skew: skew,
            isBelow: isBelow, underGapEm: isBelow ? spec.gap : 0),
        color: color)
}

/// Dedicated geometry for AMSMath's triple/quadruple dot accents.
///
/// KaTeX exposes these commands through an `\overset` macro whose payload is a
/// run of text periods. Build the dot disks directly instead: their advance and
/// clearance are stable math geometry and do not inherit text-run behavior.
func layoutMultidotAccent(_ body: LayoutBox, _ dotCount: Int, _ options: LayoutOptions)
    -> LayoutBox
{
    // The KaTeX macro wraps its dot payload in \normalsize. Math style and
    // explicit \tiny...\Huge sizing both scale this entire box later, so
    // compensate for both to keep only the mark at normal text size.
    let normalSizeScale = 1.0 / (options.sizeMultiplier * options.explicitSizeMultiplier)
    let advance =
        (FontId.mainRegular.metrics(forChar: UInt32(UInt8(ascii: ".")))?.width ?? 0.27778)
        * normalSizeScale
    let radius = 0.07 * normalSizeScale
    let markWidth = advance * Double(dotCount)
    let markHeight = radius * 2.0
    let bezier = 0.5522847498
    var commands: [PathCommand] = []
    commands.reserveCapacity(dotCount * 6)
    for index in 0..<dotCount {
        let cx = advance * (Double(index) + 0.5)
        let cy = -radius
        commands.append(.moveTo(x: cx + radius, y: cy))
        commands.append(
            .cubicTo(
                x1: cx + radius, y1: cy - bezier * radius,
                x2: cx + bezier * radius, y2: cy - radius,
                x: cx, y: cy - radius))
        commands.append(
            .cubicTo(
                x1: cx - bezier * radius, y1: cy - radius,
                x2: cx - radius, y2: cy - bezier * radius,
                x: cx - radius, y: cy))
        commands.append(
            .cubicTo(
                x1: cx - radius, y1: cy + bezier * radius,
                x2: cx - bezier * radius, y2: cy + radius,
                x: cx, y: cy + radius))
        commands.append(
            .cubicTo(
                x1: cx + bezier * radius, y1: cy + radius,
                x2: cx + radius, y2: cy + bezier * radius,
                x: cx + radius, y: cy))
        commands.append(.close)
    }

    let paddedBody = paddedToWidth(body, markWidth)
    let mark = LayoutBox(
        width: markWidth, height: markHeight, depth: 0,
        content: .svgPath(commands: commands, fill: true),
        color: options.color)
    let clearance = paddedBody.height + 3.0 * options.metrics.defaultRuleThickness
    return LayoutBox(
        width: paddedBody.width, height: clearance + markHeight, depth: paddedBody.depth,
        content: .accent(
            base: paddedBody, accent: mark, clearance: clearance, skew: 0,
            isBelow: false, underGapEm: 0),
        color: options.color)
}

func layoutAccent(
    _ label: String, _ base: ParseNode, _ isStretchy: Bool, _ isShifty: Bool,
    _ isBelow: Bool, _ options: LayoutOptions
) -> LayoutBox {
    let bodyBox = layoutNode(base, options)
    let baseW = max(bodyBox.width, 0.5)

    // Special handling for \textcircled: draw a circle around the content
    if label == "\\textcircled" {
        return layoutTextcircled(bodyBox, options)
    }

    if label == "\\dddot" || label == "\\ddddot" {
        return layoutMultidotAccent(bodyBox, label == "\\dddot" ? 3 : 4, options)
    }

    // Try KaTeX exact SVG paths first (widehat, widetilde, overgroup, etc.).
    // The path width must stay inside the accent box; renderers size their canvas from
    // DisplayList.width, so drawing wider than the box clips in an enclosing HBox.
    // KaTeX stretchy marks never shrink below their `minWidth`; the base is centered
    // in the wider mark instead.
    let accentTargetW = max(baseW, katexStretchyMinWidthEm(label) ?? 0)
    if let (commands, w, h, fill) = katexAccentPath(
        label, baseWidthEm: accentTargetW, groupLen: accentOrdgroupLen(base))
    {
        // KaTeX paths use SVG coords (y down): height=0, depth=h
        let accentBox = LayoutBox(
            width: w, height: 0, depth: h,
            content: .svgPath(commands: commands, fill: fill),
            color: options.color)
        if label != "\\vec" {
            return composeStretchy(
                paddedToWidth(bodyBox, w), accentBox,
                .accent(label, isBelow: isBelow, options), skew: 0, color: options.color)
        }
        // KaTeX `accent.ts`: clearance = min(body.height, xHeight) is used as *overlap*
        // (kern down). Equivalent position: vec bottom = body.height - overlap.
        let clearance = max(bodyBox.height - options.metrics.xHeight, 0)
        let vecSkew = (isShifty ? glyphSkew(bodyBox) : 0) + vecSkewExtraRightEm
        return LayoutBox(
            width: bodyBox.width, height: clearance + h, depth: bodyBox.depth,
            content: .accent(
                base: bodyBox, accent: accentBox, clearance: clearance,
                skew: vecSkew, isBelow: isBelow, underGapEm: 0),
            color: options.color)
    }

    // Arrow-type stretchy accents (overrightarrow, etc.)
    let useArrowPath = isStretchy && isArrowAccent(label)

    let accentBox: LayoutBox
    if useArrowPath {
        let (commands, arrowH, fillArrow): ([PathCommand], Double, Bool)
        if let (c, h) = katexStretchyPath(label, widthEm: accentTargetW) {
            (commands, arrowH, fillArrow) = (c, h, true)
        } else {
            // INTENTIONALLY UNCOVERED (defensive-fallback KEEP): reachable
            // only if `katexStretchyPath` returns nil, but `useArrowPath`
            // restricts `label` to the `isArrowAccent` set, every member of
            // which has a `katexImageData` entry whose path names all
            // resolve in `pathForName` — so the lookup never misses. Kept as
            // the correct behavior if the generated table loses an entry.
            let h = 0.3
            let c = stretchyAccentPath(label, accentTargetW, h)
            let fill = label == "\\xtwoheadrightarrow" || label == "\\xtwoheadleftarrow"
            (commands, arrowH, fillArrow) = (c, h, fill)
        }
        // Top-origin path (height 0, depth = arrow height), like the other stretchy marks.
        accentBox = LayoutBox(
            width: accentTargetW, height: 0, depth: arrowH,
            content: .svgPath(commands: commands.shiftedY(arrowH / 2), fill: fillArrow),
            color: options.color)
    } else {
        // Try text mode first for text accents (\c, \', \`, etc.), fall back to math
        let accentChar: Unicode.Scalar = {
            let ch = resolveSymbolChar(label, .text)
            if ch == (label.unicodeScalars.first ?? "?") {
                // Text mode didn't resolve (returned first char of label, likely '\')
                // so try math mode
                return resolveSymbolChar(label, .math)
            }
            return ch
        }()
        let accentCode = accentChar.value
        let accentMetrics = FontId.mainRegular.metrics(forChar: accentCode)
        let (accentW, accentH, accentD) =
            accentMetrics.map { ($0.width, $0.height, $0.depth) } ?? (bodyBox.width, 0.25, 0.0)
        accentBox = LayoutBox(
            width: accentW, height: accentH, depth: accentD,
            content: .glyph(fontId: .mainRegular, charCode: accentCode),
            color: options.color)
    }

    if useArrowPath {
        return composeStretchy(
            paddedToWidth(bodyBox, accentBox.width), accentBox,
            .accent(label, isBelow: isBelow, options), skew: 0, color: options.color)
    }

    // For shifty accents (\hat, \tilde, etc.) shift by the BASE character's skew,
    // which encodes the italic correction in math-italic fonts (e.g. M → 0.083em).
    let skew = isShifty ? glyphSkew(bodyBox) : 0

    let clearance: Double
    if isBelow {
        clearance = bodyBox.height + bodyBox.depth + accentBox.depth
    } else {
        // Clearance = how high above baseline the accent is positioned.
        // - For simple letters (M, b, o): bodyBox.height is the letter top → use directly.
        // - For a body that is itself an above-accent (\r{a}, `\tilde{\tilde{x}}`, …):
        //   use the same kern basis as a plain base (`max(0, body.height - xHeight) +
        //   correction`, with `\bar`/`\=` exceptions) instead of `innerClearance + ε`,
        //   which double-counted stacked accent depths and inflated nested spacing vs KaTeX.
        var baseClearance: Double
        if case let .accent(_, innerAccent, innerCl, _, innerIsBelow, _) = bodyBox.content,
            !innerIsBelow
        {
            // For SVG accents (height≈0, e.g. \vec): bodyBox.height = clearance + H_EM,
            // which matches KaTeX's body.height. Use min(body.height, xHeight) exactly as
            // KaTeX does: clearance = min(body.height, xHeight).
            if innerAccent.height <= 0.001 {
                // For SVG accents like \vec: KaTeX places the outer glyph accent with
                // its baseline at body.height - min(body.height, xHeight) above formula
                // baseline, i.e. max(0, body.height - xHeight).
                // ToDisplay shifts the glyph DOWN by (accentH - min(0.35, accentH))
                // so we pre-add that correction to land at the right position.
                let katexPos = max(bodyBox.height - options.metrics.xHeight, 0)
                let correction = max(accentBox.height - min(0.35, accentBox.height), 0)
                baseClearance = katexPos + correction
            } else {
                // `innerCl` already includes the inner accent glyph's depth. Using
                // `innerCl + ε` stacked another full kern on top (e.g. `\tilde{\tilde{x}}`
                // blew up to ~1.32em vs KaTeX ~0.90em). KaTeX recomputes clearance from the
                // built inner span via `min(body.height, xHeight)`; matching the non-nested
                // glyph path (`max(0, body.height - xHeight) + correction`) tracks that.
                if label == "\\bar" || label == "\\=" {
                    baseClearance = bodyBox.height
                } else {
                    // `\hat{x}` / `\dot{x}` / … enforce a 0.78056em strut so
                    // `bodyBox.height` exceeds the ink top, while KaTeX's nested accent
                    // still uses the inner span height (~0.6944em) for clearance.
                    // `\tilde{x}` keeps body ≈ visual top, so we keep `bodyBox.height`
                    // when it is not strut-inflated.
                    let innerVisualTop = innerCl + min(0.35, innerAccent.height)
                    let hForKern =
                        bodyBox.height > innerVisualTop + 0.002 ? innerVisualTop : bodyBox.height
                    let katexPos = max(hForKern - options.metrics.xHeight, 0)
                    let correction = max(accentBox.height - min(0.35, accentBox.height), 0)
                    baseClearance = katexPos + correction
                }
            }
        } else {
            // KaTeX positions glyph accents by kerning DOWN by
            // min(body.height, xHeight), so the accent baseline sits at
            //   max(0, body.height - xHeight)
            // above the formula baseline.  This keeps the accent within the
            // body's height bounds for normal-height bases and produces a
            // formula height == bodyHeight (accent adds no extra height),
            // matching KaTeX's VList.
            //
            // \bar / \= (macron) are an exception: for x-height bases (a, e, o, …)
            // body.height ≈ xHeight so katexPos ≈ 0 and the bar sits on the letter
            // (golden \text{\={a}}).  Tie macron clearance to full body height like
            // the pre-62f7ba53 engine, then apply the same small kern as before.
            if label == "\\bar" || label == "\\=" {
                baseClearance = bodyBox.height
            } else {
                let katexPos = max(bodyBox.height - options.metrics.xHeight, 0)
                let correction = max(accentBox.height - min(0.35, accentBox.height), 0)
                baseClearance = katexPos + correction
            }
        }
        // KaTeX VList places the accent so its depth-bottom edge sits at the kern
        // position.  The accent baseline is therefore depth higher than that edge.
        // Without this term, glyphs with non-zero depth (notably \tilde, depth=0.35)
        // are positioned too low, overlapping the base character.
        baseClearance += accentBox.depth
        clearance =
            label == "\\bar" || label == "\\=" ? max(baseClearance - 0.12, 0) : baseClearance
    }

    let (height, depth): (Double, Double)
    if isBelow {
        height = bodyBox.height
        depth = bodyBox.depth + accentBox.height + accentBox.depth
    } else {
        // ToDisplay shifts every glyph accent DOWN by max(0, accent.height - 0.35),
        // so the actual visual top of the accent mark = clearance + min(0.35, accent.height).
        // Use this for the layout height so nested accents (e.g. \hat{\r{a}}) see the
        // correct base height instead of the over-estimated clearance + accent.height.
        // For \hat, \bar, \dot, \ddot: also enforce KaTeX's 0.78056em strut so that
        // short bases (xHeight ≈ 0.43) produce consistent line spacing.
        let accentAboveStrutHeightEm = 0.78056
        let accentVisualTop = clearance + min(0.35, accentBox.height)
        let h: Double =
            switch label {
            case "\\hat", "\\bar", "\\=", "\\dot", "\\ddot":
                max(accentVisualTop, accentAboveStrutHeightEm)
            default:
                max(bodyBox.height, accentVisualTop)
            }
        height = h
        depth = bodyBox.depth
    }

    return LayoutBox(
        width: bodyBox.width, height: height, depth: depth,
        content: .accent(
            base: bodyBox, accent: accentBox, clearance: clearance,
            skew: skew, isBelow: isBelow, underGapEm: 0),
        color: options.color)
}
