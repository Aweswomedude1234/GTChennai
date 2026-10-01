// Verification harness: boots the dev server (if needed), loads shot definitions,
// captures screenshots + stats JSON to docs/screens/<set>/.
// Usage: node tools/harness/shots.mjs [set=phase0] [--headed] [--webgl] [--only=name]
import { chromium } from 'playwright';
import fs from 'node:fs';
import { spawn } from 'node:child_process';

const args = process.argv.slice(2);
const set = args.find((a) => !a.startsWith('--')) || 'phase0';
const headed = args.includes('--headed');
const only = args.find((a) => a.startsWith('--only='))?.slice(7);
const extra = args.find((a) => a.startsWith('--q='))?.slice(4) || '';
const PORT = 5199, BASE = `http://localhost:${PORT}/`;
const shots = JSON.parse(fs.readFileSync('tools/harness/shots.json', 'utf8'))[set];
if (!shots) { console.error('unknown set', set); process.exit(1); }

async function up() { try { const r = await fetch(BASE); return r.ok; } catch { return false; } }
let server = null;
if (!(await up())) {
  server = spawn(process.platform === 'win32' ? 'npx.cmd' : 'npx', ['vite', '--port', String(PORT)], { stdio: 'ignore', shell: true });
  for (let i = 0; i < 60 && !(await up()); i++) await new Promise((r) => setTimeout(r, 500));
}
const channel = args.find((a) => a.startsWith('--channel='))?.slice(10);
const browser = await chromium.launch({
  headless: !headed, ...(channel ? { channel } : {}),
  args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan,WebGPU', '--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist', '--disable-gpu-sandbox'],
});
const outDir = `docs/screens/${set}`;
fs.mkdirSync(outDir, { recursive: true });
const report = [];
for (const s of shots) {
  if (only && s.name !== only) continue;
  const page = await browser.newPage({ viewport: { width: s.w || 1600, height: s.h || 900 } });
  const logs = [];
  page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') logs.push(m.type() + ': ' + m.text().slice(0, 300)); });
  page.on('pageerror', (e) => logs.push('pageerror: ' + e.message));
  const url = BASE + '?' + s.q + (extra ? '&' + extra : '');
  const t0 = Date.now();
  await page.goto(url);
  try { await page.waitForFunction(() => window.__ready === true, null, { timeout: s.timeout || 90000 }); }
  catch { logs.push('TIMEOUT waiting for __ready'); }
  const loadMs = Date.now() - t0;
  await page.waitForTimeout(s.settle || 4000);
  const stats = await page.evaluate(() => window.__stats || null);
  const file = `${outDir}/${s.name}.png`;
  await page.screenshot({ path: file });
  report.push({ name: s.name, url, loadMs, stats, errors: logs.filter((l) => l.startsWith('error') || l.startsWith('pageerror')).slice(0, 10), warnings: logs.filter((l) => l.startsWith('warning')).length });
  console.log(s.name, 'load', loadMs, 'ms', JSON.stringify(stats), logs.slice(0, 6).join(' | '));
  await page.close();
}
fs.writeFileSync(`${outDir}/report.json`, JSON.stringify(report, null, 1));
await browser.close();
if (server) server.kill();
process.exit(0);
