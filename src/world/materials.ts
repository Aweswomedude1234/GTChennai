// TSL materials for the city. All weathering and detail is procedural (world-space noise),
// so thousands of buildings share a handful of materials and draw calls.
import * as THREE from 'three/webgpu';
import {
  attribute, uv, positionWorld, positionView, normalView, float, vec2, vec3, vec4, mix, step, smoothstep, fract, floor, abs, min, max, clamp,
  select, sin, pow, dot, normalize, hash, mx_noise_float, mx_fractal_noise_float, mx_worley_noise_float, uniform, texture, length, cos, time, Fn,
} from 'three/tsl';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type N = any; // TSL node typings are too strict for generic helpers
export const U = {
  night: uniform(0),     // 0 day … 1 night
  hour: uniform(12),
  wet: uniform(0),       // rain wetness 0..1
  power: uniform(1),     // 0 during power cut (except generator shops)
};

const hex = (h: string) => { const c = new THREE.Color(h); return vec3(c.r, c.g, c.b); };
const box = (x: N, y: N, x0: N | number, x1: N | number, y0: N | number, y1: N | number) =>
  step(x0 as N, x).mul(step(x, x1 as N)).mul(step(y0 as N, y)).mul(step(y, y1 as N));
const fresnel = () => pow(float(1).sub(clamp(dot(normalView, normalize(positionView).negate()), 0, 1)), 3);

// ---------------------------------------------------------------------------------- façade
export function facadeMaterial(): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.9, metalness: 0 });
  const fa = attribute<'vec4'>('fa', 'vec4'), fb = attribute<'vec4'>('fb', 'vec4');
  const paint = attribute<'vec3'>('color', 'vec3');
  const kind = fa.z, ws = fa.y, cseed = fa.x, weather = fa.w;
  const cw = fb.x, chh = fb.y, bseed = fb.w;
  const lx = uv().x.mul(cw), ly = uv().y.mul(chh);
  const wp = positionWorld;
  const along = wp.x.add(wp.z);
  const K = (k: number) => select(kind.equal(k), float(1), float(0));

  // ---- openings (metres in cell space)
  const ww = min(float(1.3), cw.mul(0.55)), wx0 = cw.sub(ww).mul(0.5), wx1 = wx0.add(ww);
  const winM = box(lx, ly, wx0, wx1, 0.9, 2.25).mul(K(1));
  const balM = box(lx, ly, cw.mul(0.5).sub(0.55), cw.mul(0.5).add(0.55), 0.06, 2.25).mul(K(2));
  const shopM = box(lx, ly, 0.1, cw.sub(0.1), 0.38, chh.sub(1.05)).mul(K(3));
  const ventM = box(lx, ly, cw.mul(0.5).sub(0.3), cw.mul(0.5).add(0.3), 1.65, 2.1).mul(K(5));
  const doorM = box(lx, ly, cw.mul(0.5).sub(0.55), cw.mul(0.5).add(0.55), 0.12, 2.2).mul(K(6));
  const stiltM = box(lx, ly, 0.0, cw, 0.0, chh.sub(0.45)).mul(K(7)).mul(float(1).sub(box(lx, ly, cw.mul(0.5).sub(0.18), cw.mul(0.5).add(0.18), 0, 10)));
  const glassM = K(4).mul(step(0.95, ly));
  const glazing = max(max(winM, balM), max(ventM, glassM));

  // ---- window frames & grilles
  const fx = min(lx.sub(wx0), wx1.sub(lx)), fy = min(ly.sub(0.9), float(2.25).sub(ly));
  const frame = winM.mul(step(min(fx, fy), 0.06));
  const gs = float(0.13);
  const sq = max(step(fract(lx.div(gs)), 0.12), step(fract(ly.div(gs)), 0.12));
  const dia = max(step(fract(lx.add(ly).div(0.18)), 0.1), step(fract(lx.sub(ly).div(0.18)), 0.1));
  const grille = select(ws.equal(1), sq, select(ws.equal(2), dia, float(0))).mul(max(winM, ventM));
  const louver = step(0.55, fract(ly.mul(11))).mul(select(ws.equal(3), float(1), float(0))).mul(winM);
  const slidingBar = step(abs(lx.sub(cw.mul(0.5))), 0.03).mul(select(ws.equal(4), float(1), float(0))).mul(winM);
  const glassGrid = K(4).mul(max(step(fract(lx.div(1.5)), 0.03), step(abs(ly.sub(0.95)), 0.05)));

  // per-cell randomness: curtains, shutters open, lit at night
  const h1 = hash(cseed.mul(9137.1)), h2 = hash(cseed.mul(5113.7)), h3 = hash(cseed.mul(771.3));
  const curtain = step(0.45, h1).mul(step(lx.sub(wx0).div(ww), h2.mul(0.8).add(0.1)));
  const curtainCol = mix(hex('#e9d8b8'), mix(hex('#c6537a'), hex('#4f7fb5'), h3), step(0.5, h2));
  const sky = mix(hex('#5f6f80'), hex('#c8d3dc'), fresnel());
  const glassCol = mix(mix(hex('#1b2026'), sky, 0.35), curtainCol.mul(0.55), curtain.mul(0.8));
  const shutterOpen = step(0.35, h1);
  const woodCol = mix(hex('#2f5d4f'), hex('#5a3a26'), step(0.5, h3));
  const winCol = select(ws.equal(3), mix(woodCol.mul(select(louver.greaterThan(0), float(0.65), float(1))), glassCol.mul(0.6), shutterOpen.mul(step(0.5, fract(lx.sub(wx0).div(ww).mul(2))).mul(0.0))), glassCol);
  const frameCol = mix(hex('#e8e4da'), paint.mul(0.75), step(0.5, hash(bseed.mul(31.7))));
  const grilleCol = mix(hex('#1c1c1c'), hex('#2f5a44'), step(0.6, hash(bseed.mul(77.1))));

  // shop interiors: open during trading hours (per-shop schedule)
  const openH = float(6.5).add(h2.mul(4)), closeH = float(20.5).add(h3.mul(3));
  const isOpen = step(openH, U.hour).mul(step(U.hour, closeH));
  const stock = vec3(mx_noise_float(vec3(lx.mul(3), ly.mul(4), cseed.mul(50))), mx_noise_float(vec3(lx.mul(2.5), ly.mul(3), cseed.mul(80))), mx_noise_float(vec3(lx.mul(3.3), ly.mul(2), cseed.mul(30)))).mul(0.5).add(0.5);
  const interior = mix(hex('#3a3128'), stock.mul(vec3(0.9, 0.7, 0.55)), smoothstep(0.4, 1.4, ly)).mul(0.55);
  const shutterCol = mix(hex('#6c6f72'), hex('#8a6a50'), mx_noise_float(vec3(along.mul(0.6), ly.mul(0.5), 3)).mul(0.5).add(0.5).mul(0.6)).mul(step(0.35, fract(ly.mul(28))).mul(0.25).add(0.75));
  const shopCol = mix(shutterCol, interior, isOpen);
  const doorCol = mix(woodCol, hex('#2a2a2a'), step(0.6, h1));
  const stiltCol = hex('#1e1c1a');

  // ---- weathering
  const grime = mx_fractal_noise_float(vec3(along.mul(0.8), wp.y.mul(0.8), 0), 3, 2, 0.5).mul(0.5).add(0.5);
  const streakN = mx_noise_float(vec3(along.mul(2.6), wp.y.mul(0.16), bseed.mul(10))).mul(0.5).add(0.5);
  const streak = smoothstep(0.55, 0.85, streakN).mul(weather).mul(0.42);
  const underWin = K(1).mul(step(ly, 0.9)).mul(max(box(lx, ly, wx0.sub(0.12), wx0.add(0.12), 0, 0.9), box(lx, ly, wx1.sub(0.12), wx1.add(0.12), 0, 0.9)))
    .mul(smoothstep(0.0, 0.9, ly)).mul(weather).mul(0.5);
  const damp = float(1).sub(smoothstep(0.0, 0.9, wp.y)).mul(0.35).mul(weather.add(0.3));
  const patchN = mx_worley_noise_float(vec2(along.mul(0.18), wp.y.mul(0.25)).add(bseed.mul(7)));
  const repaint = step(0.82, hash(floor(along.mul(0.25)).add(floor(wp.y.mul(0.3)).mul(17)).add(bseed.mul(1000)))).mul(0.07);
  let wall = paint.mul(float(0.88).add(grime.mul(0.2))).mul(float(1).add(repaint)).mul(float(1).sub(streak)).mul(float(1).sub(underWin));
  wall = mix(wall, wall.mul(vec3(0.62, 0.68, 0.6)), damp);
  wall = mix(wall, wall.mul(0.82), float(1).sub(smoothstep(0.0, 0.1, patchN)).mul(weather).mul(0.4));
  const trimCol = paint.mul(float(0.92).add(grime.mul(0.1)));
  const wallC = select(kind.equal(8), trimCol, wall);

  // ---- compose
  let col = wallC;
  col = mix(col, winCol, max(winM, balM).mul(float(1).sub(louver.mul(0))));
  col = mix(col, glassCol, max(ventM, glassM));
  col = mix(col, frameCol, frame);
  const c3 = col;
  col = mix(col, grilleCol, grille);
  col = mix(col, hex('#b7b9ba'), slidingBar);
  col = mix(col, hex('#2a3138'), glassGrid);
  const c6 = col;
  col = mix(col, shopCol, shopM);
  col = mix(col, doorCol, doorM);
  col = mix(col, stiltCol, stiltM);
  const wetDark = float(1).sub(U.wet.mul(0.25));
  m.colorNode = col.mul(wetDark);
  const dbg = new URLSearchParams(location.search).get('fdbg');
  if (dbg === 'paint') m.colorNode = paint; else if (dbg === 'uv') m.colorNode = vec3(uv().x, uv().y, 0); else if (dbg === 'kind') m.colorNode = vec3(kind.div(8), ws.div(5), weather); else if (dbg === 'wall') m.colorNode = wallC; else if (dbg === 'glass') m.colorNode = glassCol; else if (dbg === 'shop') m.colorNode = shopCol; else if (dbg === 'masks') m.colorNode = vec3(winM.add(balM), shopM.add(doorM), stiltM.add(glassM)); else if (dbg === 'frame') m.colorNode = vec3(frame, grille, slidingBar); else if (dbg === 'door') m.colorNode = doorCol; else if (dbg === 'win') m.colorNode = winCol; else if (dbg === 'c3') m.colorNode = c3; else if (dbg === 'm1') m.colorNode = mix(wallC, winCol, max(winM, balM)); else if (dbg === 'm1b') m.colorNode = mix(wallC, vec3(1, 0, 0), max(winM, balM)); else if (dbg === 'm2') m.colorNode = mix(wallC, glassCol, max(ventM, glassM)); else if (dbg === 'm3') m.colorNode = mix(wallC, frameCol, frame); else if (dbg === 'c6') m.colorNode = c6; else if (dbg === 'c9') m.colorNode = col;
  m.roughnessNode = mix(mix(float(0.92), float(0.2), max(glazing.mul(float(1).sub(curtain.mul(0.8))), 0).mul(float(1).sub(grille))), float(0.5), U.wet.mul(0.4));
  // ---- night: lit windows (warm incandescent or cool tube) and open shops
  const litFrac = mix(float(0.15), float(0.62), U.night).mul(select(U.hour.greaterThan(23.5), float(0.3), float(1))).mul(select(U.hour.lessThan(5), float(0.2), float(1)));
  const lit = step(hash(cseed.mul(3331.7)), litFrac).mul(U.power);
  const litCol = mix(hex('#ffbe73'), hex('#dcecff'), step(0.55, h2)).mul(mix(float(0.6), float(1.1), curtain));
  const winLight = max(winM, max(balM, max(ventM, glassM))).mul(float(1).sub(grille.mul(0.8))).mul(lit).mul(U.night);
  const shopLight = shopM.mul(isOpen).mul(smoothstep(0.3, 1.6, ly)).mul(U.night.mul(0.9).add(0.1));
  m.emissiveNode = litCol.mul(winLight.mul(2.2)).add(stock.mul(hex('#fff2dd')).mul(shopLight.mul(1.6)));
  return m;
}

// ---------------------------------------------------------------------------------- generic props
export function genericMaterial(): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.8 });
  const gm = attribute<'vec4'>('gm', 'vec4');
  const base = attribute<'vec3'>('color', 'vec3');
  const t = gm.x, u = uv();
  const T = (k: number) => select(t.equal(k), float(1), float(0));
  const wp = positionWorld;
  const n1 = mx_noise_float(wp.mul(1.7)).mul(0.5).add(0.5);
  const n2 = mx_fractal_noise_float(wp.mul(0.45), 3, 2, 0.5).mul(0.5).add(0.5);
  let col = base.mul(float(0.85).add(n1.mul(0.3)));
  // corrugated tin: ridges + rust
  const corr = sin(u.x.mul(82)).mul(0.5).add(0.5);
  const rust = smoothstep(0.55, 0.8, n2).mul(0.6);
  col = mix(col, mix(base.mul(float(0.75).add(corr.mul(0.35))), hex('#7a4a2a'), rust), T(1));
  // tarpaulin wrinkles
  col = mix(col, base.mul(float(0.8).add(mx_noise_float(vec3(u.x.mul(3), u.y.mul(3), gm.w.mul(9))).mul(0.25))), T(2));
  // water tank ribs
  col = mix(col, base.mul(float(0.8).add(step(0.5, fract(wp.y.mul(2.5))).mul(0.25))), T(3));
  // mangalore tiles
  const row = fract(u.y.mul(3.3)), tileId = hash(floor(u.x.mul(4)).add(floor(u.y.mul(3.3)).mul(91)));
  col = mix(col, base.mul(float(0.7).add(tileId.mul(0.35))).mul(float(1).sub(step(0.85, row).mul(0.45))).mul(float(1).sub(smoothstep(0.6, 0.9, n2).mul(0.35))), T(4));
  // concrete terrace: grime and water stains
  col = mix(col, base.mul(float(0.75).add(n2.mul(0.35))).mul(float(1).sub(smoothstep(0.65, 0.75, mx_noise_float(wp.mul(0.3))).mul(0.25))), T(5));
  // granite speckle
  col = mix(col, base.mul(float(0.8).add(step(0.7, hash(floor(wp.mul(40)).dot(vec3(1, 57, 113)))).mul(0.35))), T(10));
  m.colorNode = col.mul(float(1).sub(U.wet.mul(0.2)));
  m.roughnessNode = mix(gm.y, float(0.25), U.wet.mul(0.6).mul(T(5).add(T(10)).add(T(1))));
  m.metalnessNode = select(t.equal(6), float(0.35), select(t.equal(1), float(0.3), float(0)));
  m.emissiveNode = base.mul(T(8)).mul(gm.z).mul(mix(float(0.15), float(3.5), U.night)).mul(U.power);
  return m;
}

// ---------------------------------------------------------------------------------- signs
export function signMaterial(map: THREE.Texture): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.55 });
  const sg = attribute<'vec4'>('sg', 'vec4');
  const c = texture(map, uv());
  m.colorNode = c.rgb.mul(float(1).sub(U.wet.mul(0.1)));
  // backlit flex boards glow at night; others get spill from the tube light
  m.emissiveNode = c.rgb.mul(mix(float(0.0), select(sg.x.greaterThan(0.5), float(1.1), float(0.18)), U.night)).mul(U.power);
  return m;
}

// ---------------------------------------------------------------------------------- roads
export function roadMaterial(): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.9 });
  const rd = attribute<'vec4'>('rd', 'vec4'); // wear, rank, width, seed
  const u = uv(); // x: metres along, y: -1..1 across
  const wp = positionWorld.xz;
  const fine = mx_noise_float(vec3(wp.mul(6), 0)).mul(0.5).add(0.5);
  const mid = mx_fractal_noise_float(vec3(wp.mul(0.35), 1), 3, 2, 0.5).mul(0.5).add(0.5);
  let col = mix(hex('#3c3c3b'), hex('#5e5b55'), rd.x.add(mid.mul(0.35).sub(0.15))).mul(float(0.9).add(fine.mul(0.2)));
  // patch repairs: rectangles of fresher asphalt
  const cell = floor(vec2(u.x.div(3.2), u.y.mul(1.6)));
  const patchH = hash(cell.x.add(cell.y.mul(31)).add(rd.w.mul(97)));
  col = mix(col, hex('#2c2c2c').mul(float(0.9).add(fine.mul(0.2))), step(0.86, patchH).mul(0.85));
  // potholes (more on low-rank roads)
  const ph = mx_noise_float(vec3(wp.mul(0.9), 7)).mul(0.5).add(0.5);
  const holeT = mix(float(0.78), float(0.86), rd.y.div(6));
  const hole = smoothstep(holeT, holeT.add(0.02), ph);
  col = mix(col, hex('#2a2621'), hole.mul(0.9));
  // dusty sand creeping in from the edges
  const edge = smoothstep(0.62, 1.0, abs(u.y).add(mid.mul(0.15)));
  col = mix(col, hex('#8c7c62'), edge.mul(0.75));
  // markings: faded centre dashes on secondary+ roads
  const halfW = rd.z.mul(0.5);
  const dash = step(abs(u.y).mul(halfW), 0.065).mul(step(fract(u.x.div(7.5)), 0.4)).mul(step(3.5, rd.y));
  const worn = smoothstep(0.35, 0.65, mx_noise_float(vec3(wp.mul(0.7), 3)).mul(0.5).add(0.5));
  col = mix(col, hex('#d6d3c8'), dash.mul(worn).mul(0.85));
  const edgeLine = step(abs(abs(u.y).mul(halfW).sub(halfW.sub(0.35))), 0.06).mul(step(4.5, rd.y)).mul(worn);
  col = mix(col, hex('#d6d3c8'), edgeLine.mul(0.6));
  // wetness + puddles in potholes and edges
  const puddle = max(hole, edge.mul(smoothstep(0.55, 0.7, mid))).mul(U.wet);
  m.colorNode = col.mul(float(1).sub(U.wet.mul(0.35))).mul(float(1).sub(puddle.mul(0.3)));
  m.roughnessNode = mix(float(0.88), float(0.08), max(U.wet.mul(0.55), puddle));
  return m;
}

// ---------------------------------------------------------------------------------- ground / areas
export function groundMaterial(): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.95 });
  const gk = attribute<'vec4'>('gk', 'vec4'); // kind, -, -, -
  const base = attribute<'vec3'>('color', 'vec3');
  const wp = positionWorld.xz;
  const n1 = mx_fractal_noise_float(vec3(wp.mul(0.08), 0), 4, 2, 0.5).mul(0.5).add(0.5);
  const n2 = mx_noise_float(vec3(wp.mul(1.3), 2)).mul(0.5).add(0.5);
  const n3 = mx_noise_float(vec3(wp.mul(5), 4)).mul(0.5).add(0.5);
  const k = gk.x;
  const K = (v: number) => select(k.equal(v), float(1), float(0));
  // 0 = urban ground: packed earth / broken concrete / weeds
  const earth = mix(hex('#7d6e58'), hex('#958a78'), n1);
  const concrete = hex('#8f8b83').mul(float(0.85).add(n3.mul(0.2)));
  const weeds = hex('#5d6a3a').mul(float(0.8).add(n3.mul(0.4)));
  let urban = mix(earth, concrete, smoothstep(0.45, 0.6, n2));
  urban = mix(urban, weeds, smoothstep(0.72, 0.8, n1).mul(0.7));
  // 1 park grass, 2 playground earth, 3 sand, 4 granite paving, 5 cemetery, 6 wet sand
  const grass = mix(hex('#4f6a2e'), hex('#7a8a45'), n1).mul(float(0.85).add(n3.mul(0.3)));
  const dirt = mix(hex('#9c8665'), hex('#b09a78'), n2).mul(float(0.9).add(n3.mul(0.15)));
  const sand = mix(hex('#d4bf93'), hex('#e2d1aa'), n1).mul(float(0.92).add(n3.mul(0.12)));
  const tiles = fract(wp.mul(1.6));
  const granite = hex('#8a857e').mul(float(0.8).add(hash(floor(wp.mul(1.6)).dot(vec2(1, 57))).mul(0.3))).mul(float(1).sub(max(step(tiles.x, 0.03), step(tiles.y, 0.03)).mul(0.3)));
  const wetSand = mix(hex('#8f7a58'), hex('#a68f69'), n2);
  let col = urban.mul(K(0)).add(grass.mul(K(1))).add(dirt.mul(K(2))).add(sand.mul(K(3))).add(granite.mul(K(4))).add(mix(grass, dirt, 0.5).mul(K(5))).add(wetSand.mul(K(6)));
  col = col.mul(base);
  m.colorNode = col.mul(float(1).sub(U.wet.mul(0.3)));
  m.roughnessNode = mix(float(0.95), float(0.35), U.wet.mul(K(4).add(K(0).mul(0.5))));
  return m;
}

// ---------------------------------------------------------------------------------- sea
export function seaMaterial(coastU: THREE.Node): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.25, metalness: 0.05 });
  void coastU;
  const wp = positionWorld.xz;
  const sd = attribute<'float'>('sd', 'float'); // distance from shore, metres
  const w1 = mx_noise_float(vec3(wp.mul(0.05).add(vec2(time.mul(0.02), 0)), time.mul(0.05))).mul(0.5).add(0.5);
  const w2 = mx_noise_float(vec3(wp.mul(0.4).add(vec2(time.mul(-0.08), time.mul(0.03))), 1)).mul(0.5).add(0.5);
  const deep = mix(hex('#3f5a5a'), hex('#566f68'), w1);
  const shallow = hex('#7a8a72');
  let col = mix(shallow, deep, smoothstep(0, 60, sd)).mul(float(0.9).add(w2.mul(0.2)));
  // surf lines rolling in
  const surfPhase = fract(sd.div(14).add(time.mul(0.11)).add(w1.mul(0.4)));
  const surf = smoothstep(0.86, 0.95, surfPhase).mul(float(1).sub(smoothstep(10, 70, sd))).mul(smoothstep(0.35, 0.6, w2));
  const shoreFoam = float(1).sub(smoothstep(0, 6, sd)).mul(smoothstep(0.3, 0.7, w2.add(sin(time.mul(0.7).add(wp.y.mul(0.05))).mul(0.3))));
  col = mix(col, hex('#e8ece6'), max(surf, shoreFoam).mul(0.85));
  m.colorNode = mix(col, hex('#c9d4d6'), fresnel().mul(0.35));
  m.roughnessNode = mix(float(0.12), float(0.6), max(surf, shoreFoam));
  return m;
}

export function waterMaterial(): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.15 });
  const wp = positionWorld.xz;
  const n = mx_noise_float(vec3(wp.mul(0.25), time.mul(0.1))).mul(0.5).add(0.5);
  m.colorNode = mix(mix(hex('#3d4a3a'), hex('#4f5e46'), n), hex('#a9b6b8'), fresnel().mul(0.5));
  m.roughnessNode = float(0.12).add(n.mul(0.1));
  return m;
}

export function emissiveLampMaterial(color: string): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.4 });
  m.colorNode = hex(color);
  m.emissiveNode = hex(color).mul(mix(float(0), float(4), U.night)).mul(U.power);
  return m;
}

export { vec4, length, cos, Fn };
