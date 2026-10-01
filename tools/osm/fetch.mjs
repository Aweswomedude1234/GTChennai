// Fetch raw OSM data for each region in data/regions.json via Overpass API.
// Output: data/osm/<region>.raw.json (Overpass JSON). ODbL — credited in docs/CREDITS.md.
import fs from 'node:fs';
const regions = JSON.parse(fs.readFileSync('data/regions.json', 'utf8'));
const ENDPOINTS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
for (const r of regions) {
  const out = `data/osm/${r.id}.raw.json`;
  if (fs.existsSync(out) && !process.argv.includes('--force')) { console.log('skip', r.id); continue; }
  const [s, w, n, e] = r.bbox;
  const q = `[out:json][timeout:180];(
    way["highway"](${s},${w},${n},${e});
    way["building"](${s},${w},${n},${e});
    way["natural"](${s},${w},${n},${e});
    way["landuse"](${s},${w},${n},${e});
    way["leisure"](${s},${w},${n},${e});
    way["amenity"](${s},${w},${n},${e});
    way["railway"](${s},${w},${n},${e});
    way["waterway"](${s},${w},${n},${e});
    relation["natural"="water"](${s},${w},${n},${e});
    node["amenity"](${s},${w},${n},${e});
    node["shop"](${s},${w},${n},${e});
    node["man_made"](${s},${w},${n},${e});
    node["highway"="traffic_signals"](${s},${w},${n},${e});
  );out body;>;out skel qt;`;
  let ok = false;
  for (const ep of ENDPOINTS) {
    try {
      const res = await fetch(ep, { method: 'POST', body: 'data=' + encodeURIComponent(q), headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'GTIndian-personal-project/0.1' } });
      if (!res.ok) throw new Error(res.status + ' ' + (await res.text()).slice(0, 200));
      const txt = await res.text();
      fs.writeFileSync(out, txt);
      console.log(r.id, (txt.length / 1e6).toFixed(1), 'MB from', ep);
      ok = true; break;
    } catch (err) { console.warn('fail', ep, err.message); }
  }
  if (!ok) process.exitCode = 1;
}
