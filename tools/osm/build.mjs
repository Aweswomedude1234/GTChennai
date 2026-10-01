// Convert raw Overpass JSON into the GTIndian region format consumed by the engine.
// Output: godot/packs/<city>/regions/<id>/{meta.json, chunks/<cx>_<cz>.json}
// Coordinates: local metres, x = east, z = south (three.js: north is -z), y = up.
import fs from 'node:fs';
import path from 'node:path';

const CHUNK = 200;
const regions = JSON.parse(fs.readFileSync('data/regions.json', 'utf8'));
const only = process.argv[2];

// Deterministic hash → [0,1)
function hash(n) { n = (n ^ 61) ^ (n >>> 16); n = Math.imul(n, 9); n ^= n >>> 4; n = Math.imul(n, 0x27d4eb2d); n ^= n >>> 15; return (n >>> 0) / 4294967296; }
function rng(seed) { let s = seed >>> 0 || 1; return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return (s >>> 0) / 4294967296; }; }
function pickW(r, weights) { let t = r() * weights.reduce((a, b) => a + b, 0); for (let i = 0; i < weights.length; i++) { t -= weights[i]; if (t <= 0) return i; } return weights.length - 1; }
const r1 = (v) => Math.round(v * 10) / 10;

// Road widths in metres (carriageway). Derived in STYLE_BIBLE §Roads.
const ROAD = {
  motorway: { w: 14, rank: 6 }, trunk: { w: 14, rank: 6 }, primary: { w: 13, rank: 5 }, primary_link: { w: 6.5, rank: 4 },
  secondary: { w: 10, rank: 4 }, secondary_link: { w: 6, rank: 3 }, tertiary: { w: 8, rank: 3 }, tertiary_link: { w: 5.5, rank: 3 },
  unclassified: { w: 6, rank: 2 }, residential: { w: 5.6, rank: 2 }, living_street: { w: 4.2, rank: 1 }, service: { w: 4, rank: 1 },
  pedestrian: { w: 5, rank: 0 }, footway: { w: 2, rank: 0 }, path: { w: 1.8, rank: 0 }, track: { w: 3.5, rank: 1 }, construction: { w: 6, rank: 2 },
};

for (const region of regions) {
  if (only && region.id !== only) continue;
  const raw = JSON.parse(fs.readFileSync(`data/osm/${region.id}.raw.json`, 'utf8'));
  const [lat0, lon0] = region.origin;
  const kx = Math.cos(lat0 * Math.PI / 180) * 111320, kz = 110574;
  const proj = (lat, lon) => [(lon - lon0) * kx, -(lat - lat0) * kz];
  const [s, w, n, e] = region.bbox;
  const [minX, minZ] = proj(n, w), [maxX, maxZ] = proj(s, e);

  const nodes = new Map(), ways = new Map(), rels = [];
  for (const el of raw.elements) {
    if (el.type === 'node') nodes.set(el.id, el);
    else if (el.type === 'way') ways.set(el.id, el);
    else rels.push(el);
  }
  const wayPts = (wy) => { const out = []; for (const id of wy.nodes) { const nd = nodes.get(id); if (nd) out.push(proj(nd.lat, nd.lon)); } return out; };

  // ---------- Roads ----------
  const roads = [];
  const nodeUse = new Map();
  for (const wy of ways.values()) {
    const t = wy.tags || {};
    if (!t.highway || !ROAD[t.highway] || t.area === 'yes') continue;
    if (t.access === 'no' && t.highway !== 'primary') continue;
    const def = ROAD[t.highway];
    let wdt = def.w;
    if (t.lanes) wdt = Math.max(wdt * 0.6, Math.min(24, parseFloat(t.lanes) * 3.3));
    if (t.width && !isNaN(parseFloat(t.width))) wdt = parseFloat(t.width);
    const pts = wayPts(wy);
    if (pts.length < 2) continue;
    for (const id of wy.nodes) nodeUse.set(id, (nodeUse.get(id) || 0) + 1);
    roads.push({
      id: wy.id, cls: t.highway, rank: def.rank, w: r1(wdt), oneway: t.oneway === 'yes' ? 1 : 0,
      name: t.name || '', nameTa: t['name:ta'] || '', bridge: t.bridge === 'yes' ? 1 : 0, layer: parseInt(t.layer || '0') || 0,
      lit: t.lit === 'yes' ? 1 : 0, nodes: wy.nodes, pts: pts.flat().map(r1),
    });
  }
  // Junctions: OSM nodes used by ≥2 road ways or appearing mid-way twice.
  const junctions = [];
  const junctionIdx = new Map();
  for (const r of roads) for (const id of r.nodes) {
    if ((nodeUse.get(id) || 0) >= 2 && !junctionIdx.has(id)) {
      const nd = nodes.get(id); if (!nd) continue;
      junctionIdx.set(id, junctions.length);
      junctions.push({ id, p: proj(nd.lat, nd.lon).map(r1), roads: [], signal: nd.tags?.highway === 'traffic_signals' ? 1 : 0 });
    }
  }
  for (const [ri, r] of roads.entries()) for (const id of r.nodes) { const j = junctionIdx.get(id); if (j !== undefined) junctions[j].roads.push(ri); }
  // Node index per road: replace osm ids with junction index or -1 (keeps graph compact)
  for (const r of roads) { r.j = r.nodes.map((id) => junctionIdx.get(id) ?? -1); delete r.nodes; }

  // Spatial hash of road segments for frontage queries
  const SH = 25, segGrid = new Map();
  roads.forEach((r, ri) => {
    if (r.rank === 0 && r.cls !== 'pedestrian') return;
    for (let i = 0; i < r.pts.length / 2 - 1; i++) {
      const ax = r.pts[i * 2], az = r.pts[i * 2 + 1], bx = r.pts[i * 2 + 2], bz = r.pts[i * 2 + 3];
      const x0 = Math.floor((Math.min(ax, bx) - 30) / SH), x1 = Math.floor((Math.max(ax, bx) + 30) / SH);
      const z0 = Math.floor((Math.min(az, bz) - 30) / SH), z1 = Math.floor((Math.max(az, bz) + 30) / SH);
      for (let gx = x0; gx <= x1; gx++) for (let gz = z0; gz <= z1; gz++) {
        const k = gx + ',' + gz; if (!segGrid.has(k)) segGrid.set(k, []); segGrid.get(k).push([ri, ax, az, bx, bz]);
      }
    }
  });
  function nearestRoad(x, z) {
    const cell = segGrid.get(Math.floor(x / SH) + ',' + Math.floor(z / SH)); if (!cell) return null;
    let best = null, bd = 1e9;
    for (const [ri, ax, az, bx, bz] of cell) {
      const dx = bx - ax, dz = bz - az, L = dx * dx + dz * dz || 1;
      let t = ((x - ax) * dx + (z - az) * dz) / L; t = Math.max(0, Math.min(1, t));
      const px = ax + dx * t, pz = az + dz * t, d = Math.hypot(x - px, z - pz);
      if (d < bd) { bd = d; best = { ri, d, px, pz }; }
    }
    return best;
  }

  // ---------- Areas ----------
  const areas = [];
  const landuseGrid = []; // [poly, kind] for point-in-polygon district classification
  const areaKind = (t) => {
    if (t.natural === 'water' || t.water || t.landuse === 'reservoir' || t.landuse === 'basin') return 'water';
    if (t.natural === 'beach') return 'beach';
    if (t.leisure === 'park' || t.leisure === 'garden' || t.landuse === 'grass' || t.landuse === 'village_green' || t.natural === 'scrub') return 'park';
    if (t.leisure === 'pitch' || t.leisure === 'playground' || t.landuse === 'recreation_ground') return 'ground';
    if (t.landuse === 'cemetery') return 'cemetery';
    if (t.landuse === 'religious' || (t.amenity === 'place_of_worship' && !t.building)) return 'religious';
    if (t.landuse === 'commercial' || t.landuse === 'retail' || t.landuse === 'retail;commercial') return 'commercial';
    if (t.landuse === 'residential') return 'residential';
    if (t.amenity === 'school' || t.amenity === 'college' || t.amenity === 'hospital') return 'institution';
    if (t.amenity === 'parking') return 'parking';
    if (t.landuse === 'construction') return 'construction';
    return null;
  };
  for (const wy of ways.values()) {
    const t = wy.tags || {};
    if (t.building || t.highway) continue;
    const k = areaKind(t); if (!k) continue;
    const pts = wayPts(wy); if (pts.length < 4) continue;
    areas.push({ k, name: t.name || '', nameTa: t['name:ta'] || '', pts: pts.flat().map(r1) });
    landuseGrid.push([pts, k]);
  }
  // Water multipolygon relations (outer rings only)
  for (const rel of rels) {
    if (rel.tags?.natural !== 'water') continue;
    for (const m of rel.members || []) if (m.type === 'way' && m.role === 'outer' && ways.has(m.ref)) {
      const pts = wayPts(ways.get(m.ref)); if (pts.length > 3) areas.push({ k: 'water', name: rel.tags.name || '', nameTa: '', pts: pts.flat().map(r1) });
    }
  }
  function pip(pts, x, z) { let c = false; for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) { const [xi, zi] = pts[i], [xj, zj] = pts[j]; if ((zi > z) !== (zj > z) && x < (xj - xi) * (z - zi) / (zj - zi) + xi) c = !c; } return c; }

  // Sea: stitch coastline ways and close against the east edge of the bbox.
  const coast = [];
  for (const wy of ways.values()) if (wy.tags?.natural === 'coastline') coast.push(wayPts(wy));
  let coastLine = [];
  if (coast.length) {
    const segs = coast.slice();
    coastLine = segs.shift();
    let guard = 0;
    while (segs.length && guard++ < 1000) {
      const end = coastLine[coastLine.length - 1], start = coastLine[0];
      let bi = -1, mode = 0, bd = 60;
      segs.forEach((sg, i) => {
        const c = [[Math.hypot(sg[0][0] - end[0], sg[0][1] - end[1]), 0], [Math.hypot(sg.at(-1)[0] - end[0], sg.at(-1)[1] - end[1]), 1],
          [Math.hypot(sg.at(-1)[0] - start[0], sg.at(-1)[1] - start[1]), 2], [Math.hypot(sg[0][0] - start[0], sg[0][1] - start[1]), 3]];
        for (const [d, m] of c) if (d < bd) { bd = d; bi = i; mode = m; }
      });
      if (bi < 0) break;
      const sg = segs.splice(bi, 1)[0];
      if (mode === 0) coastLine = coastLine.concat(sg.slice(1));
      else if (mode === 1) coastLine = coastLine.concat(sg.reverse().slice(1));
      else if (mode === 2) coastLine = sg.concat(coastLine.slice(1));
      else coastLine = sg.reverse().concat(coastLine.slice(1));
    }
    coastLine.sort((a, b) => a[1] - b[1]);
    // extend to bbox top/bottom
    const top = coastLine[0], bot = coastLine.at(-1);
    coastLine.unshift([top[0], minZ - 400]); coastLine.push([bot[0], maxZ + 400]);
  }

  // ---------- POIs ----------
  const pois = [];
  const shopPts = [];
  for (const nd of nodes.values()) {
    const t = nd.tags; if (!t) continue;
    const p = proj(nd.lat, nd.lon).map(r1);
    if (t.shop || ['restaurant', 'fast_food', 'cafe', 'bank', 'pharmacy', 'clinic', 'atm', 'fuel'].includes(t.amenity)) shopPts.push(p);
    if (t.highway === 'traffic_signals') continue;
    const kind = t.shop ? 'shop:' + t.shop : t.amenity ? 'amenity:' + t.amenity : t.man_made ? 'mm:' + t.man_made : null;
    if (kind) pois.push({ k: kind, p, name: t.name || '' });
  }
  const landmarks = [];
  for (const wy of ways.values()) {
    const t = wy.tags || {};
    if (t.amenity === 'place_of_worship' || t.building === 'lighthouse' || t.building === 'train_station' || t.tourism === 'museum' || t.amenity === 'police') {
      const pts = wayPts(wy); if (!pts.length) continue;
      const c = pts.reduce((a, p) => [a[0] + p[0] / pts.length, a[1] + p[1] / pts.length], [0, 0]);
      landmarks.push({ id: wy.id, k: t.building === 'lighthouse' ? 'lighthouse' : t.amenity === 'police' ? 'police' : t.building === 'train_station' ? 'station' : t.religion || (t.building === 'church' ? 'christian' : 'worship'), name: t.name || '', nameTa: t['name:ta'] || '', c: c.map(r1), building: !!t.building });
    }
  }
  const templeMain = landmarks.find((l) => /Kapaleeshwarar Temple complex/.test(l.name));
  const templeC = templeMain ? templeMain.c : [0, 0];

  // ---------- Railways (elevated MRTS etc.) ----------
  const rails = [];
  for (const wy of ways.values()) {
    const t = wy.tags || {};
    if (t.railway !== 'rail' || t.tunnel === 'yes') continue;
    rails.push({ id: wy.id, elevated: t.bridge === 'yes' || (parseInt(t.layer || '0') > 0) ? 1 : 0, layer: parseInt(t.layer || '0') || 0, pts: wayPts(wy).flat().map(r1) });
  }

  // ---------- Buildings ----------
  const shopGrid = new Map();
  for (const p of shopPts) { const k = Math.floor(p[0] / 50) + ',' + Math.floor(p[1] / 50); shopGrid.set(k, (shopGrid.get(k) || 0) + 1); }
  const chunks = new Map();
  let bcount = 0; const kindCount = {};
  const special = new Map(); // building way id -> landmark
  for (const l of landmarks) if (l.building) special.set(l.id, l);

  for (const wy of ways.values()) {
    const t = wy.tags || {};
    if (!t.building || t.building === 'roof' || t.building === 'construction' && !t['building:levels']) continue;
    let pts = wayPts(wy);
    if (pts.length < 4) continue;
    if (Math.hypot(pts[0][0] - pts.at(-1)[0], pts[0][1] - pts.at(-1)[1]) < 0.01) pts.pop();
    // orientation: make CCW in (x, z) with z south → use signed area; we want outward normals = (dz, -dx) for CCW in x-right,z-down
    let A = 0; for (let i = 0; i < pts.length; i++) { const [x1, z1] = pts[i], [x2, z2] = pts[(i + 1) % pts.length]; A += x1 * z2 - x2 * z1; }
    if (A < 0) { pts.reverse(); A = -A; }
    const area = A / 2;
    if (area < 12) continue;
    // simplify near-collinear points
    const simp = [];
    for (let i = 0; i < pts.length; i++) {
      const p0 = pts[(i - 1 + pts.length) % pts.length], p1 = pts[i], p2 = pts[(i + 1) % pts.length];
      const cross = (p1[0] - p0[0]) * (p2[1] - p1[1]) - (p1[1] - p0[1]) * (p2[0] - p1[0]);
      const l1 = Math.hypot(p1[0] - p0[0], p1[1] - p0[1]), l2 = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
      if (Math.abs(cross) / Math.max(1e-6, l1 * l2) > 0.03 && l1 > 0.4) simp.push(p1);
    }
    if (simp.length >= 3) pts = simp;
    const cx = pts.reduce((a, p) => a + p[0], 0) / pts.length, cz = pts.reduce((a, p) => a + p[1], 0) / pts.length;
    if (cx < minX || cx > maxX || cz < minZ || cz > maxZ) continue;
    const seed = (wy.id * 2654435761) >>> 0;
    const r = rng(seed);

    // Frontage per edge: outward normal (for CCW with A>0 in x,z-with-z-down) is (dz, -dx)/len
    const edges = [], edgeRoad = [];
    let bestRank = -1;
    for (let i = 0; i < pts.length; i++) {
      const [x1, z1] = pts[i], [x2, z2] = pts[(i + 1) % pts.length];
      const dx = x2 - x1, dz = z2 - z1, L = Math.hypot(dx, dz);
      if (L < 2.5) { edges.push(0); edgeRoad.push(-1); continue; }
      const nx = dz / L, nz = -dx / L;
      const mx = (x1 + x2) / 2 + nx, mz = (z1 + z2) / 2 + nz;
      const nr = nearestRoad(mx, mz);
      let f = 0, fr = -1;
      if (nr) {
        const rd = roads[nr.ri];
        const toX = nr.px - mx, toZ = nr.pz - mz, tl = Math.hypot(toX, toZ) || 1;
        const facing = (toX * nx + toZ * nz) / tl;
        if (nr.d < rd.w / 2 + 14 && facing > 0.55) { f = rd.rank + 1; fr = nr.ri; bestRank = Math.max(bestRank, rd.rank); }
      }
      edges.push(f); edgeRoad.push(fr);
    }
    // District context
    let lu = null; for (const [poly, k] of landuseGrid) if ((k === 'commercial' || k === 'residential' || k === 'religious' || k === 'institution') && pip(poly, cx, cz)) { lu = k; if (k !== 'residential') break; }
    const shops = shopGrid.get(Math.floor(cx / 50) + ',' + Math.floor(cz / 50)) || 0;
    const dTemple = Math.hypot(cx - templeC[0], cz - templeC[1]);
    const lm = special.get(wy.id);

    let kind;
    if (lm) kind = lm.k === 'hindu' ? 'temple' : lm.k === 'christian' ? 'church' : lm.k === 'muslim' ? 'mosque' : lm.k === 'lighthouse' ? 'lighthouse' : lm.k === 'station' ? 'station' : lm.k === 'police' ? 'police' : 'civic';
    else if (t.building === 'train_station') kind = 'station';
    else if (t.building === 'church' || t.building === 'cathedral') kind = 'church';
    else if (t.building === 'temple' || t.building === 'mosque') kind = t.building;
    else if (lu === 'institution' || t.amenity === 'school' || t.amenity === 'hospital' || t.building === 'school' || t.building === 'hospital' || t.building === 'public') kind = 'institution';
    else if (area > 1800) kind = r() < 0.5 ? 'institution' : 'apartment';
    else if (t.building === 'apartments' || area > 550) kind = 'apartment';
    else if (dTemple < 420 && area < 260 && bestRank <= 3) kind = r() < 0.65 ? 'agraharam' : 'oldhouse';
    else if (bestRank >= 3 || lu === 'commercial' || (bestRank >= 2 && shops > 1)) kind = 'commercial';
    else if (bestRank >= 2 && r() < 0.22) kind = 'commercial';
    else kind = r() < 0.08 ? 'informal' : 'residential';
    if (kind === 'informal' && area > 120) kind = 'residential';

    // Levels (G+n → n+1 floors). Distributions from STYLE_BIBLE §Buildings.
    let levels = parseInt(t['building:levels'] || '0');
    if (!levels && t.height) levels = Math.max(1, Math.round(parseFloat(t.height) / 3.2));
    if (!levels) {
      switch (kind) {
        case 'agraharam': levels = 1 + pickW(r, [45, 45, 10]); break;
        case 'oldhouse': levels = 1 + pickW(r, [30, 50, 20]); break;
        case 'informal': levels = 1 + pickW(r, [70, 30]); break;
        case 'residential': levels = 1 + pickW(r, [8, 32, 34, 18, 8]); break;
        case 'commercial': levels = 1 + pickW(r, [6, 26, 34, 22, 12]); break;
        case 'apartment': levels = 3 + pickW(r, [15, 35, 25, 15, 10]); break;
        case 'institution': levels = 1 + pickW(r, [15, 35, 30, 20]); break;
        case 'temple': levels = 1; break;
        case 'church': levels = 2; break;
        default: levels = 2 + pickW(r, [40, 40, 20]);
      }
    }
    kindCount[kind] = (kindCount[kind] || 0) + 1;
    const ck = Math.floor((cx - minX) / CHUNK) + '_' + Math.floor((cz - minZ) / CHUNK);
    if (!chunks.has(ck)) chunks.set(ck, { b: [] });
    const b = { f: pts.flat().map(r1), k: kind, l: levels, s: seed, e: edges, r: edgeRoad };
    if (t.height) b.h = parseFloat(t.height);
    if (lm?.name || t.name) b.n = lm?.name || t.name;
    if (t.building === 'lighthouse') b.h = parseFloat(t.height) || 45.7;
    chunks.get(ck).b.push(b);
    bcount++;
  }

  // ---------- Write ----------
  const outDir = `godot/packs/${region.city}/regions/${region.id}`;
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(path.join(outDir, 'chunks'), { recursive: true });
  const chunkList = [];
  for (const [k, c] of chunks) { fs.writeFileSync(path.join(outDir, 'chunks', k + '.json'), JSON.stringify(c)); chunkList.push(k); }
  const meta = {
    id: region.id, name: region.name, city: region.city, origin: region.origin, chunkSize: CHUNK,
    bounds: [r1(minX), r1(minZ), r1(maxX), r1(maxZ)], chunks: chunkList,
    roads, junctions, areas, rails, coast: coastLine.flat().map(r1), pois, landmarks,
    generated: new Date().toISOString(), source: 'OpenStreetMap contributors (ODbL)',
  };
  fs.writeFileSync(path.join(outDir, 'meta.json'), JSON.stringify(meta));
  console.log(region.id, { roads: roads.length, junctions: junctions.length, areas: areas.length, buildings: bcount, chunks: chunkList.length, rails: rails.length, pois: pois.length, landmarks: landmarks.length, coastPts: coastLine.length }, kindCount);
  console.log('meta size', (fs.statSync(path.join(outDir, 'meta.json')).size / 1e6).toFixed(2), 'MB', 'bounds', meta.bounds);
}
