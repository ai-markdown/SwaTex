// Measure KaTeX 0.16.47 output in headless Chromium (font-size 20px) and screenshot each formula.
// Usage: node katex-browser.mjs <web> <katexOutDir>
import {createRequire} from 'node:module';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import path from 'node:path';
const [web, kdir] = process.argv.slice(2);
const {chromium} = createRequire(path.join(web, 'package.json'))('playwright');
const data = JSON.parse(readFileSync(path.join(kdir, 'katex-results.json'), 'utf8'));
mkdirSync(path.join(kdir, 'png'), {recursive: true});
const browser = await chromium.launch();
const page = await browser.newPage({deviceScaleFactor: 2, viewport: {width: 1400, height: 900}});
const css = `<link rel="stylesheet" href="file://${path.join(kdir, 'katex-dist/katex.min.css')}">
<style>body{margin:0;background:#fff;font-family:serif}.row{padding:4px;display:block;white-space:nowrap}
.probe{display:inline-block;font-size:20px;line-height:normal}.probe .katex{font-size:1em}.probe .katex-display{margin:0}
.bl{display:inline-block;width:0;height:0}</style>`;
const out = [];
const CH = 100;
for (let i = 0; i < data.results.length; i += CH) {
  const chunk = data.results.slice(i, i + CH);
  const html = `<!doctype html><html><head><meta charset="utf-8">${css}</head><body>` +
    chunk.map(r => `<div class="row"><span class="probe" id="p_${r.id}">${r.html}</span><span class="bl" id="b_${r.id}"></span></div>`).join('') + '</body></html>';
  const f = path.join(kdir, `page-${i}.html`); writeFileSync(f, html);
  await page.goto('file://' + f);
  await page.evaluate(() => document.fonts.ready);
  const m = await page.evaluate(ids => ids.map(id => {
    const p = document.getElementById('p_' + id), b = document.getElementById('b_' + id);
    const pr = p.getBoundingClientRect(), br = b.getBoundingClientRect();
    const inner = p.querySelector('.katex-html') || p;
    const ir = inner.getBoundingClientRect();
    return {id, width: ir.width, boxWidth: pr.width, ascent: br.top - pr.top, descent: pr.bottom - br.top};
  }), chunk.map(r => r.id));
  for (const r of m) {
    try { await page.locator('#p_' + r.id).screenshot({path: path.join(kdir, 'png', r.id + '.png'), timeout: 5000}); r.png = true; } catch { r.png = false; }
    out.push(r);
  }
}
await browser.close();
writeFileSync(path.join(kdir, 'katex-metrics.json'), JSON.stringify({browser: 'playwright chromium', metrics: out}));
console.log('measured', out.length);
