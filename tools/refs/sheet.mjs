// Download selected reference thumbnails and render contact sheets (local only, not shipped).
import fs from 'node:fs';
import { chromium } from 'playwright';
const refs = JSON.parse(fs.readFileSync('data/refs/refs.json', 'utf8'));
const groups = JSON.parse(process.argv[2]);
const UA = { 'User-Agent': 'GTIndian-personal-research/0.1 (non-commercial game reference)' };
const browser = await chromium.launch();
for (const [name, ids] of Object.entries(groups)) {
  const imgs = [];
  for (const id of ids) {
    const r = refs[id]; if (!r) continue;
    const f = `data/refs/images/${id}.jpg`;
    if (!fs.existsSync(f)) { await new Promise((ok) => setTimeout(ok, 1200)); const b = Buffer.from(await (await fetch(r.thumb, { headers: UA })).arrayBuffer()); fs.writeFileSync(f, b); }
    imgs.push(`<figure><img src="data:image/jpeg;base64,${fs.readFileSync(f).toString('base64')}"><figcaption>${id} ${r.title.slice(5, 60)}</figcaption></figure>`);
  }
  const page = await browser.newPage({ viewport: { width: 1600, height: 1200 } });
  await page.setContent(`<style>body{margin:0;display:grid;grid-template-columns:1fr 1fr;gap:4px;background:#111;font:12px sans-serif;color:#fff}figure{margin:0;height:596px;position:relative}img{width:100%;height:100%;object-fit:contain}figcaption{position:absolute;left:4px;top:4px;background:#000a;padding:2px 4px}</style>${imgs.join('')}`);
  await page.waitForTimeout(300);
  await page.screenshot({ path: `data/refs/images/sheet_${name}.png` });
  await page.close();
  console.log('sheet', name, imgs.length);
}
await browser.close();
