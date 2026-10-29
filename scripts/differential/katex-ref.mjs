// KaTeX reference at the version rehype-katex resolves in Web e9ec1799, emulating rehype-katex's try/fallback.
// Usage: node katex-ref.mjs <web> <corpus.jsonl> <outDir>
import {createRequire} from 'node:module';
import {readFileSync, writeFileSync, mkdirSync, cpSync} from 'node:fs';
import path from 'node:path';
const [web, corpusPath, out] = process.argv.slice(2);
const rk = createRequire(createRequire(path.join(web, 'packages/engine/package.json')).resolve('rehype-katex'));
const katexPath = rk.resolve('katex');
const katex = rk('katex');
const katexDir = path.dirname(path.dirname(katexPath));
const rows = readFileSync(corpusPath, 'utf8').trim().split('\n').map(l => JSON.parse(l));
const now = () => Number(process.hrtime.bigint()) / 1e6;
const results = [];
for (const r of rows) {
  const opts = {displayMode: r.mode === 'display'};
  const warns = []; const prev = console.warn; console.warn = (...a) => warns.push(a.join(' '));
  let status = 'ok', error = null, html = null;
  const t0 = now();
  try { html = katex.renderToString(r.tex, {...opts, throwOnError: true}); }
  catch (e) {
    status = 'error'; error = `${e.name}: ${e.message}`.slice(0, 300);
    try { html = katex.renderToString(r.tex, {...opts, strict: 'ignore', throwOnError: false}); }
    catch (e2) { status = 'hard-error'; html = `<span class="katex-error" style="color:#cc0000">${r.tex.replace(/[&<>]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;'}[c]))}</span>`; }
  }
  const first = now() - t0;
  const reps = [];
  for (let i = 0; i < 5; i++) { const a = now(); try { katex.renderToString(r.tex, {...opts, throwOnError: false, strict: 'ignore'}); } catch {} reps.push(now() - a); }
  console.warn = prev;
  reps.sort((a, b) => a - b);
  results.push({id: r.id, status, error, warnings: warns.length, firstMs: first, warmMs: reps[2], html});
}
mkdirSync(out, {recursive: true});
writeFileSync(path.join(out, 'katex-results.json'), JSON.stringify({katexVersion: katex.version, katexPath, results}, null, 0));
cpSync(path.join(katexDir, 'dist'), path.join(out, 'katex-dist'), {recursive: true});
console.log({version: katex.version, path: katexPath, n: results.length, errors: results.filter(r => r.status !== 'ok').length});
