// Differential dumper for SwaTex fixtures. Copy into a RaTeX v0.1.15 checkout as
// crates/ratex-layout/src/bin/dl_dump.rs and build with
// `cargo build --release -p ratex-layout --bin dl_dump`. Reads JSONL
// {"id","tex","mode"} and prints {"id","ok","error","dl"} with the full
// serialized display list, using the same pipeline as ratex-ffi.
use ratex_layout::{layout, to_display_list, validate_layout, LayoutOptions};
use ratex_parser::parser::parse;
use ratex_types::math_style::MathStyle;
use std::io::{self, BufRead, Write};

fn main() {
    let stdin = io::stdin();
    let mut out = io::stdout().lock();
    std::panic::set_hook(Box::new(|_| {}));
    for line in stdin.lock().lines().map_while(Result::ok) {
        if line.trim().is_empty() { continue; }
        let v: serde_json::Value = serde_json::from_str(&line).expect("json");
        let id = v["id"].clone();
        let tex = v["tex"].as_str().unwrap_or("").to_string();
        let display = v["mode"].as_str().unwrap_or("display") != "inline";
        let r = std::panic::catch_unwind(|| -> Result<serde_json::Value, String> {
            let ast = parse(&tex).map_err(|e| e.to_string())?;
            let style = if display { MathStyle::Display } else { MathStyle::Text };
            let opts = LayoutOptions::default().with_style(style);
            let lbox = layout(&ast, &opts);
            validate_layout(&lbox)?;
            let dl = to_display_list(&lbox);
            serde_json::to_value(&dl).map_err(|e| e.to_string())
        });
        let res = match r {
            Ok(Ok(dl)) => serde_json::json!({"id": id, "ok": true, "dl": dl}),
            Ok(Err(e)) => serde_json::json!({"id": id, "ok": false, "error": e}),
            Err(_) => serde_json::json!({"id": id, "ok": false, "error": "panic", "panic": true}),
        };
        writeln!(out, "{}", res).expect("write");
    }
}
