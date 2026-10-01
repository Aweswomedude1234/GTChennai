// Region-level (global) geometry: ground, roads, junctions, footpaths, areas, stepped temple tanks,
// beach slope and the sea. Built once on the main thread from meta.json.
import * as THREE from 'three/webgpu';
import { MeshBuilder, GENERIC_SPEC, GM, hexToLin, type V3 } from './gen/meshBuilder';
import { roadMaterial, groundMaterial, seaMaterial, waterMaterial, genericMaterial, U } from './materials';
import { hashf, mulberry, range } from '../engine/rng';

export interface Road { id: number; cls: string; rank: number; w: number; oneway: number; name: string; nameTa: string; bridge: number; layer: number; lit: number; pts: number[]; j: number[] }
export interface Junction { id: number; p: [number, number]; roads: number[]; signal: number }
export interface Area { k: string; name: string; nameTa: string; pts: number[] }
export interface Landmark { id: number; k: string; name: string; nameTa: string; c: [number, number]; building: boolean }
export interface RegionMeta {
  id: string; name: string; city: string; origin: [number, number]; chunkSize: number; bounds: [number, number, number, number];
  chunks: string[]; roads: Road[]; junctions: Junction[]; areas: Area[]; rails: { id: number; elevated: number; layer: number; pts: number[] }[];
  coast: number[]; pois: { k: string; p: [number, number]; name: string }[]; landmarks: Landmark[];
}

const ROAD_SPEC = [{ name: 'position', size: 3 }, { name: 'normal', size: 3 }, { name: 'uv', size: 2 }, { name: 'rd', size: 4 }];
const GROUND_SPEC = [{ name: 'position', size: 3 }, { name: 'normal', size: 3 }, { name: 'color', size: 3 }, { name: 'gk', size: 4 }];
const SEA_LEVEL = -0.35;

export function toGeometry(b: { attrs: Record<string, Float32Array>; index: Uint32Array }): THREE.BufferGeometry {
  const g = new THREE.BufferGeometry();
  for (const [k, v] of Object.entries(b.attrs)) {
    const size = k === 'uv' ? 2 : k === 'sd' ? 1 : k === 'position' || k === 'normal' || k === 'color' ? 3 : 4;
    g.setAttribute(k, new THREE.BufferAttribute(v, size));
  }
  g.setIndex(new THREE.BufferAttribute(b.index, 1));
  g.computeBoundingSphere();
  return g;
}

export class Region {
  readonly group = new THREE.Group();
  coastX: (z: number) => number = () => Infinity;
  /** spatial hash of road segments for queries (nearest road, on-road test) */
  private segGrid = new Map<string, number[]>();
  readonly SH = 30;

  constructor(readonly meta: RegionMeta) {
    this.buildCoast();
    this.buildGround();
    this.buildRoads();
    this.buildSea();
    this.indexRoads();
  }

  private buildCoast() {
    const c = this.meta.coast;
    if (c.length < 4) return;
    const pts: [number, number][] = []; for (let i = 0; i < c.length; i += 2) pts.push([c[i], c[i + 1]]);
    this.coastX = (z: number) => {
      if (z <= pts[0][1]) return pts[0][0];
      for (let i = 0; i < pts.length - 1; i++) if (z <= pts[i + 1][1]) { const t = (z - pts[i][1]) / (pts[i + 1][1] - pts[i][1] || 1); return pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t; }
      return pts[pts.length - 1][0];
    };
  }

  // ------------------------------------------------------------------ ground + areas + tanks + beach
  private buildGround() {
    const [x0, z0, x1, z1] = this.meta.bounds;
    const M = 300, B = new MeshBuilder(GROUND_SPEC);
    const BEACH_IN = 70;
    const hasCoast = this.meta.coast.length > 0;
    // land polygon: west edge + coast offset inland (sea side is built separately)
    const land: THREE.Vector2[] = [];
    const zs: number[] = []; for (let z = z0 - M; z <= z1 + M; z += 20) zs.push(z);
    if (hasCoast) {
      land.push(new THREE.Vector2(x0 - M, z0 - M));
      for (const z of zs) land.push(new THREE.Vector2(Math.min(x1 + M, this.coastX(z) - BEACH_IN), z));
      land.push(new THREE.Vector2(x0 - M, z1 + M));
    } else land.push(new THREE.Vector2(x0 - M, z0 - M), new THREE.Vector2(x1 + M, z0 - M), new THREE.Vector2(x1 + M, z1 + M), new THREE.Vector2(x0 - M, z1 + M));
    // holes: temple tanks / ponds (stepped)
    const holes: THREE.Vector2[][] = [];
    const tanks: Area[] = [];
    for (const a of this.meta.areas) if (a.k === 'water' && polyArea(a.pts) < 120000) {
      const pts = toV2(a.pts); if (THREE.ShapeUtils.isClockWise(pts)) pts.reverse();
      holes.push(pts); tanks.push(a);
    }
    const groundTris = THREE.ShapeUtils.triangulateShape(land, holes);
    const all = land.concat(...holes);
    const flat: number[] = []; for (const p of all) flat.push(p.x, p.y);
    B.polygon(flat, groundTris.flat(), 0, true, { color: [1, 1, 1], gk: [0, 0, 0, 0] });

    // areas on top (y = 0.012), clamped away from the beach strip
    const kindMap: Record<string, number> = { park: 1, ground: 2, beach: 3, religious: 4, cemetery: 5, construction: 2 };
    for (const a of this.meta.areas) {
      const k = kindMap[a.k]; if (k === undefined) continue;
      const pts = toV2(a.pts);
      if (hasCoast) for (const p of pts) p.x = Math.min(p.x, this.coastX(p.y) - BEACH_IN);
      if (Math.abs(polyAreaV(pts)) < 4) continue;
      let tris: number[][] = [];
      try { tris = THREE.ShapeUtils.triangulateShape(pts, []); } catch { continue; }
      const f: number[] = []; for (const p of pts) f.push(p.x, p.y);
      const tint = a.k === 'religious' ? 1 : 0.92 + hashf(a.pts.length * 7 + Math.round(a.pts[0])) * 0.16;
      B.polygon(f, tris.flat(), 0.012 + k * 0.002, true, { color: [tint, tint, tint], gk: [k, 0, 0, 0] });
    }
    // stepped tanks: granite steps down to the water
    const W = new MeshBuilder(GROUND_SPEC);
    for (const t of tanks) this.buildTank(t, B, W);
    // beach strip: sand slopes from inland (y=0) to below sea level
    if (hasCoast) {
      const S = [-BEACH_IN, -40, -15, 0, 8, 20, 45];
      const Y = (s: number) => s <= -BEACH_IN ? 0 : s < 0 ? -0.32 * (s + BEACH_IN) / BEACH_IN : -0.32 - (s / 45) * 1.6;
      for (let zi = 0; zi < zs.length - 1; zi++) for (let si = 0; si < S.length - 1; si++) {
        const za = zs[zi], zb = zs[zi + 1], sa = S[si], sb = S[si + 1];
        const p = (s: number, z: number): V3 => [this.coastX(z) + s, Y(s), z];
        const kind = (s: number) => (s > -12 ? 6 : 3);
        const q0 = p(sa, za), q1 = p(sb, za), q2 = p(sb, zb), q3 = p(sa, zb);
        B.quad(q0, q1, q2, q3, [0, 1, 0], { color: [1, 1, 1], gk: [kind((sa + sb) / 2), 0, 0, 0] });
      }
    }
    const g = toGeometry(B.build());
    g.computeVertexNormals();
    const mesh = new THREE.Mesh(g, groundMaterial());
    mesh.receiveShadow = true; mesh.name = 'ground';
    this.group.add(mesh);
    if (W.vcount) { const wm = new THREE.Mesh(toGeometry(W.build()), waterMaterial()); wm.receiveShadow = true; this.group.add(wm); }
  }

  private buildTank(a: Area, B: MeshBuilder, W: MeshBuilder) {
    let ring = toV2(a.pts); if (THREE.ShapeUtils.isClockWise(ring)) ring.reverse();
    const steps = 9, rise = 0.28, tread = 0.55;
    const granite: V3 = [0.95, 0.93, 0.9];
    for (let s = 0; s < steps; s++) {
      const inner = insetPoly(ring, tread);
      const yTop = -s * rise, yBot = -(s + 1) * rise;
      for (let i = 0; i < ring.length; i++) {
        const a0 = ring[i], a1 = ring[(i + 1) % ring.length], b0 = inner[i], b1 = inner[(i + 1) % inner.length];
        // tread (horizontal)
        B.quad([a0.x, yTop, a0.y], [a1.x, yTop, a1.y], [b1.x, yTop, b1.y], [b0.x, yTop, b0.y], [0, 1, 0], { color: granite, gk: [4, 0, 0, 0] });
        // riser (vertical, facing into the tank)
        const dx = b1.x - b0.x, dz = b1.y - b0.y, L = Math.hypot(dx, dz) || 1;
        const nrm: V3 = [-dz / L, 0, dx / L];
        B.quad([b0.x, yTop, b0.y], [b1.x, yTop, b1.y], [b1.x, yBot, b1.y], [b0.x, yBot, b0.y], nrm, { color: [0.85, 0.83, 0.8], gk: [4, 0, 0, 0] });
      }
      ring = inner;
    }
    // water surface
    const f: number[] = []; for (const p of ring) f.push(p.x, p.y);
    try { W.polygon(f, THREE.ShapeUtils.triangulateShape(ring, []).flat(), -steps * rise + 0.9, true, { color: [1, 1, 1], gk: [0, 0, 0, 0] }); } catch { /* skip */ }
  }

  // ------------------------------------------------------------------ roads
  private buildRoads() {
    const R = new MeshBuilder(ROAD_SPEC), K = new MeshBuilder(GENERIC_SPEC);
    const roads = this.meta.roads, junc = this.meta.junctions;
    const jr = new Float32Array(junc.length);
    for (const r of roads) if (r.rank > 0 || r.cls === 'pedestrian') for (const j of r.j) if (j >= 0) jr[j] = Math.max(jr[j], r.w / 2);
    const Y = 0.03;
    for (const [ri, r] of roads.entries()) {
      if (r.rank === 0 && r.cls !== 'pedestrian') continue;
      const P = r.pts, n = P.length / 2;
      if (n < 2) continue;
      const rnd = mulberry(r.id);
      const wear = Math.min(1, (r.rank <= 2 ? 0.55 : 0.3) + rnd() * 0.4);
      const hw = r.w / 2;
      let acc = 0;
      const left: V3[] = [], right: V3[] = [], us: number[] = [];
      for (let i = 0; i < n; i++) {
        const px = P[i * 2], pz = P[i * 2 + 1];
        const ax = i > 0 ? px - P[i * 2 - 2] : P[i * 2 + 2] - px, az = i > 0 ? pz - P[i * 2 - 1] : P[i * 2 + 3] - pz;
        const bx = i < n - 1 ? P[i * 2 + 2] - px : ax, bz = i < n - 1 ? P[i * 2 + 3] - pz : az;
        const la = Math.hypot(ax, az) || 1, lb = Math.hypot(bx, bz) || 1;
        let tx = ax / la + bx / lb, tz = az / la + bz / lb; const lt = Math.hypot(tx, tz) || 1; tx /= lt; tz /= lt;
        const cosHalf = Math.max(0.5, (ax / la) * tx + (az / la) * tz);
        const nx = -tz * hw / cosHalf, nz = tx * hw / cosHalf;
        if (i > 0) acc += la;
        left.push([px + nx, Y, pz + nz]); right.push([px - nx, Y, pz - nz]); us.push(acc);
      }
      for (let i = 0; i < n - 1; i++) {
        R.quad(left[i], right[i], right[i + 1], left[i + 1], [0, 1, 0], { rd: [wear, r.rank, r.w, rnd()] }, [[us[i], 1], [us[i], -1], [us[i + 1], -1], [us[i + 1], 1]]);
      }
      // footpaths with kerbs on tertiary+ roads, cut back near junctions
      if (r.rank >= 3) this.footpaths(r, ri, K, jr, rnd);
    }
    // junction patches
    for (const [ji, j] of junc.entries()) {
      const rad = jr[ji]; if (rad <= 0 || j.roads.length < 2) continue;
      const seg = 14, base = R.vcount;
      R.vert({ position: [j.p[0], Y + 0.004, j.p[1]], normal: [0, 1, 0], uv: [0, 0], rd: [0.4, 3, rad * 2, 0] });
      for (let s = 0; s <= seg; s++) {
        const a = (s / seg) * Math.PI * 2;
        R.vert({ position: [j.p[0] + Math.cos(a) * rad * 1.08, Y + 0.004, j.p[1] + Math.sin(a) * rad * 1.08], normal: [0, 1, 0], uv: [0, 0.45], rd: [0.4, 3, rad * 2, 0] });
      }
      for (let s = 0; s < seg; s++) R.index.push(base, base + 2 + s, base + 1 + s);
    }
    const rm = new THREE.Mesh(toGeometry(R.build()), roadMaterial());
    rm.receiveShadow = true; rm.name = 'roads';
    this.group.add(rm);
    if (K.vcount) { const km = new THREE.Mesh(toGeometry(K.build()), genericMaterial()); km.receiveShadow = true; km.castShadow = false; km.name = 'footpaths'; this.group.add(km); }
  }

  private footpaths(r: Road, ri: number, K: MeshBuilder, jr: Float32Array, rnd: () => number) {
    const P = r.pts, n = P.length / 2, hw = r.w / 2;
    const fw = r.rank >= 5 ? range(rnd, 1.8, 2.5) : range(rnd, 1.2, 1.8);
    const kerbH = 0.17;
    const paver = hexToLin(rnd() < 0.5 ? '#8c8478' : '#8a5a4a');
    const kerbPainted = r.rank >= 5;
    void ri;
    for (let i = 0; i < n - 1; i++) {
      const ax = P[i * 2], az = P[i * 2 + 1], bx = P[i * 2 + 2], bz = P[i * 2 + 3];
      const L = Math.hypot(bx - ax, bz - az); if (L < 1) continue;
      const tx = (bx - ax) / L, tz = (bz - az) / L, nx = -tz, nz = tx;
      // trim near junctions at either end
      const ja = r.j[i], jb = r.j[i + 1];
      const ta = ja >= 0 ? jr[ja] + fw + 1.5 : 0, tb = jb >= 0 ? jr[jb] + fw + 1.5 : 0;
      if (ta + tb >= L - 0.5) continue;
      const sx = ax + tx * ta, sz = az + tz * ta, ex = bx - tx * tb, ez = bz - tz * tb, len = L - ta - tb;
      for (const side of [-1, 1]) {
        if (rnd() < 0.12) continue; // missing footpath stretches are common
        const o0 = hw * side, o1 = (hw + fw) * side;
        const p = (s: number, o: number, y: number): V3 => [sx + tx * s + nx * o, y, sz + tz * s + nz * o];
        const top: [V3, V3, V3, V3] = [p(0, o0, kerbH), p(len, o0, kerbH), p(len, o1, kerbH), p(0, o1, kerbH)];
        K.quad(...top, [0, 1, 0], { color: paver, gm: [GM.Granite, 0.85, 0, rnd()] }, [[0, 0], [len, 0], [len, fw], [0, fw]]);
        // kerb face toward the road (black/yellow painted on main roads)
        const kc: V3 = kerbPainted ? [0.5, 0.42, 0.05] : [0.45, 0.44, 0.42];
        K.quad(p(0, o0, 0), p(len, o0, 0), p(len, o0, kerbH), p(0, o0, kerbH), [-nx * side, 0, -nz * side], { color: kc, gm: [kerbPainted ? GM.Stucco : GM.Concrete, 0.8, 0, rnd()] }, [[0, 0], [len, 0], [len, kerbH], [0, kerbH]]);
      }
    }
  }

  // ------------------------------------------------------------------ sea
  private buildSea() {
    if (!this.meta.coast.length) return;
    const [, z0, , z1] = this.meta.bounds;
    const S = [-8, 0, 6, 12, 20, 30, 45, 65, 90, 130, 190, 280, 420, 650, 1000, 1600, 2600, 4000];
    const pos: number[] = [], sd: number[] = [], idx: number[] = [];
    const zs: number[] = []; for (let z = z0 - 1500; z <= z1 + 1500; z += 25) zs.push(z);
    for (const z of zs) for (const s of S) { pos.push(this.coastX(z) + s, SEA_LEVEL, z); sd.push(Math.max(0, s - 2)); }
    const cols = S.length;
    for (let zi = 0; zi < zs.length - 1; zi++) for (let si = 0; si < cols - 1; si++) {
      const a = zi * cols + si, b = a + 1, c = a + cols, d = c + 1;
      idx.push(a, c, b, b, c, d);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('sd', new THREE.Float32BufferAttribute(sd, 1));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(new Float32Array(pos.length).map((_, i) => (i % 3 === 1 ? 1 : 0)), 3));
    g.setIndex(idx);
    g.computeBoundingSphere();
    const m = new THREE.Mesh(g, seaMaterial(U.night as unknown as THREE.Node));
    m.name = 'sea'; m.receiveShadow = true;
    this.group.add(m);
  }

  // ------------------------------------------------------------------ queries
  private indexRoads() {
    this.meta.roads.forEach((r, ri) => {
      for (let i = 0; i < r.pts.length / 2 - 1; i++) {
        const ax = r.pts[i * 2], az = r.pts[i * 2 + 1], bx = r.pts[i * 2 + 2], bz = r.pts[i * 2 + 3];
        const gx0 = Math.floor(Math.min(ax, bx) / this.SH), gx1 = Math.floor(Math.max(ax, bx) / this.SH);
        const gz0 = Math.floor(Math.min(az, bz) / this.SH), gz1 = Math.floor(Math.max(az, bz) / this.SH);
        for (let gx = gx0; gx <= gx1; gx++) for (let gz = gz0; gz <= gz1; gz++) {
          const k = gx + ',' + gz; let c = this.segGrid.get(k); if (!c) this.segGrid.set(k, (c = []));
          c.push(ri, i);
        }
      }
    });
  }
  /** nearest drivable road point within `maxD` metres */
  nearestRoad(x: number, z: number, maxD = 40, minRank = 1): { ri: number; seg: number; px: number; pz: number; d: number; t: number; dirX: number; dirZ: number } | null {
    let best = null as ReturnType<Region['nearestRoad']>, bd = maxD;
    const g0x = Math.floor((x - maxD) / this.SH), g1x = Math.floor((x + maxD) / this.SH), g0z = Math.floor((z - maxD) / this.SH), g1z = Math.floor((z + maxD) / this.SH);
    const seen = new Set<number>();
    for (let gx = g0x; gx <= g1x; gx++) for (let gz = g0z; gz <= g1z; gz++) {
      const c = this.segGrid.get(gx + ',' + gz); if (!c) continue;
      for (let k = 0; k < c.length; k += 2) {
        const ri = c[k], i = c[k + 1], key = ri * 4096 + i; if (seen.has(key)) continue; seen.add(key);
        const r = this.meta.roads[ri]; if (r.rank < minRank) continue;
        const ax = r.pts[i * 2], az = r.pts[i * 2 + 1], bx = r.pts[i * 2 + 2], bz = r.pts[i * 2 + 3];
        const dx = bx - ax, dz = bz - az, L2 = dx * dx + dz * dz || 1;
        const t = Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / L2));
        const px = ax + dx * t, pz = az + dz * t, d = Math.hypot(x - px, z - pz);
        if (d < bd) { bd = d; const L = Math.sqrt(L2); best = { ri, seg: i, px, pz, d, t, dirX: dx / L, dirZ: dz / L }; }
      }
    }
    return best;
  }
}

function toV2(f: number[]) { const out: THREE.Vector2[] = []; for (let i = 0; i < f.length; i += 2) out.push(new THREE.Vector2(f[i], f[i + 1])); if (out.length > 2 && out[0].distanceTo(out[out.length - 1]) < 0.01) out.pop(); return out; }
function polyArea(f: number[]) { let a = 0; for (let i = 0, n = f.length / 2; i < n; i++) { const j = (i + 1) % n; a += f[i * 2] * f[j * 2 + 1] - f[j * 2] * f[i * 2 + 1]; } return Math.abs(a / 2); }
function polyAreaV(p: THREE.Vector2[]) { let a = 0; for (let i = 0; i < p.length; i++) { const j = (i + 1) % p.length; a += p[i].x * p[j].y - p[j].x * p[i].y; } return a / 2; }
/** inset a CCW (in three's ShapeUtils sense) polygon by d using edge-bisector offsets */
function insetPoly(p: THREE.Vector2[], d: number): THREE.Vector2[] {
  const n = p.length, out: THREE.Vector2[] = [];
  const sign = THREE.ShapeUtils.isClockWise(p) ? -1 : 1;
  for (let i = 0; i < n; i++) {
    const a = p[(i - 1 + n) % n], b = p[i], c = p[(i + 1) % n];
    const e1 = new THREE.Vector2().subVectors(b, a).normalize(), e2 = new THREE.Vector2().subVectors(c, b).normalize();
    const n1 = new THREE.Vector2(-e1.y, e1.x).multiplyScalar(sign), n2 = new THREE.Vector2(-e2.y, e2.x).multiplyScalar(sign);
    const bis = n1.clone().add(n2); const l = bis.length() || 1; bis.divideScalar(l);
    const cosH = Math.max(0.35, bis.dot(n1));
    out.push(b.clone().add(bis.multiplyScalar(d / cosH)));
  }
  return out;
}
