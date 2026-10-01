// Collect reference image metadata (+ 800px thumbnails) from Wikimedia Commons categories.
// Thumbnails stay local (gitignored); data/refs/refs.json records source + licence for each.
import fs from 'node:fs';
const CATS = JSON.parse(fs.readFileSync('data/refs/categories.json', 'utf8'));
const out = fs.existsSync('data/refs/refs.json') ? JSON.parse(fs.readFileSync('data/refs/refs.json', 'utf8')) : {};
const UA = { 'User-Agent': 'GTIndian-personal-research/0.1 (non-commercial game reference)' };
for (const [topic, cats] of Object.entries(CATS)) {
  for (const cat of cats) {
    if (Object.values(out).some((r) => r.cat === cat)) { console.log('have', cat); continue; }
    const gen = cat.startsWith('search:') ? `generator=search&gsrnamespace=6&gsrlimit=30&gsrsearch=${encodeURIComponent(cat.slice(7))}` : `generator=categorymembers&gcmtitle=${encodeURIComponent('Category:' + cat)}&gcmtype=file&gcmlimit=40`;
    const u = `https://commons.wikimedia.org/w/api.php?action=query&format=json&${gen}&prop=imageinfo&iiprop=url|extmetadata|size&iiurlwidth=800`;
    await new Promise((r) => setTimeout(r, 2500));
    const res = await fetch(u, { headers: UA }); const txt = await res.text();
    if (!txt.startsWith('{')) { console.log('rate limited at', cat); break; }
    const j = JSON.parse(txt);
    const pages = Object.values(j.query?.pages || {});
    let n = 0;
    for (const p of pages) {
      const ii = p.imageinfo?.[0]; if (!ii || !/\.(jpe?g|png)$/i.test(p.title)) continue;
      const lic = ii.extmetadata?.LicenseShortName?.value || '?';
      const id = p.pageid;
      out[id] = { topic, cat, title: p.title, page: ii.descriptionurl, licence: lic, artist: (ii.extmetadata?.Artist?.value || '').replace(/<[^>]+>/g, '').slice(0, 80), w: ii.width, h: ii.height, thumb: ii.thumburl };
      n++;
    }
    console.log(topic, cat, n);
    fs.writeFileSync('data/refs/refs.json', JSON.stringify(out, null, 1));
  }
}
fs.writeFileSync('data/refs/refs.json', JSON.stringify(out, null, 1));
