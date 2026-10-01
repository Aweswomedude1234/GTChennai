// Procedural Chennai building generator (runs in the chunk worker).
// One quad per façade "cell" (bay × floor) so the façade shader knows exactly what to draw,
// plus real geometry for the cues that matter in silhouette: chajjas over every opening,
// balconies, parapets, AC units, roof water tanks, mumty headrooms, tiled roofs, shop fronts.
import { ShapeUtils, Vector2 } from 'three';
import { MeshBuilder, FACADE_SPEC, GENERIC_SPEC, SIGN_SPEC, GM, hexToLin, type V3 } from './meshBuilder';
import { mulberry, pick, pickW, range, type Rng } from '../../engine/rng';

export interface BuildingIn { f: number[]; k: string; l: number; s: number; e: number[]; r?: number[]; h?: number; n?: string }
export interface Style {
  floorH: number; groundH: Record<string, [number, number]>; bayW: [number, number];
  paint: Record<string, string[]>; accent: string[]; windowStyles: Record<string, number[]>;
  chajjaDepth: [number, number]; balconyChance: Record<string, number>; acChance: Record<string, number>;
  tankChance: number; mumtyChance: number; dishChance: number; shopW: [number, number]; awningChance: number;
  awningColors: string[]; tileRoof: string; kaavi: string;
}
export interface SignReq { cell: number; kind: 'flex' | 'paint' | 'upper'; seed: number; trade: number; road: number; upper?: number }
export interface ShopInfo { x: number; z: number; nx: number; nz: number; w: number; trade: number; seed: number; sign: number }
export interface GenCtx {
  facade: MeshBuilder; generic: MeshBuilder; sign: MeshBuilder;
  signs: SignReq[]; maxSigns: number; shops: ShopInfo[];
  lights: number[]; // x,y,z,type (0 tube,1 window warm)
  colliders: { f: number[]; h: number }[];
  detail: boolean; trades: { w: number }[];
}

export const enum Cell { Plain = 0, Window = 1, Balcony = 2, Shop = 3, Glass = 4, Vent = 5, Door = 6, Stilt = 7, Trim = 8 }

const jitter = (c: V3, r: Rng, amt: number): V3 => { const k = 1 + (r() - 0.5) * 2 * amt; return [c[0] * k, c[1] * k, c[2] * k]; };
const mix3 = (a: V3, b: V3, t: number): V3 => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

export function newCtx(detail: boolean, maxSigns: number, trades: { w: number }[]): GenCtx {
  return {
    facade: new MeshBuilder(FACADE_SPEC), generic: new MeshBuilder(GENERIC_SPEC), sign: new MeshBuilder(SIGN_SPEC),
    signs: [], maxSigns, shops: [], lights: [], colliders: [], detail, trades,
  };
}

const SIGN_COLS = 4, SIGN_ROWS = 25;
export const SIGN_ATLAS = { w: 1024, h: 2048, cw: 256, ch: 80, cols: SIGN_COLS, rows: SIGN_ROWS };
function signUV(cell: number): [number, number, number, number] {
  const c = cell % SIGN_COLS, rr = Math.floor(cell / SIGN_COLS) % SIGN_ROWS;
  const pad = 2;
  const u0 = (c * SIGN_ATLAS.cw + pad) / SIGN_ATLAS.w, u1 = ((c + 1) * SIGN_ATLAS.cw - pad) / SIGN_ATLAS.w;
  // ImageBitmap textures are uploaded without flipY: v=0 is the top row
  const v0 = (rr * SIGN_ATLAS.ch + pad) / SIGN_ATLAS.h, v1 = ((rr + 1) * SIGN_ATLAS.ch - pad) / SIGN_ATLAS.h;
  return [u0, v0, u1, v1];
}

export function genBuilding(b: BuildingIn, style: Style, ctx: GenCtx) {
  const r = mulberry(b.s);
  const n = b.f.length / 2;
  const P: [number, number][] = []; for (let i = 0; i < n; i++) P.push([b.f[i * 2], b.f[i * 2 + 1]]);
  const kind = b.k;
  const sacred = kind === 'temple' || kind === 'church' || kind === 'mosque';
  let levels = Math.max(1, b.l);
  const commercial = kind === 'commercial';
  const gh = commercial ? range(r, 3.6, 4.2) : kind === 'institution' ? 3.6 : range(r, 3.0, 3.3);
  const fh = style.floorH + (r() - 0.5) * 0.2;
  let H = gh + (levels - 1) * fh;
  if (b.h && b.h > 0) { H = b.h; levels = Math.max(1, Math.round((H - gh) / fh) + 1); }
  const palette = style.paint[kind] || style.paint.residential;
  const paint = jitter(hexToLin(pick(r, palette)), r, 0.08);
  const accent = hexToLin(pick(r, style.accent));
  const wsList = style.windowStyles[kind] || style.windowStyles.default;
  const ws = kind === 'apartment' && r() < 0.15 ? 5 : pick(r, wsList);
  const weather = range(r, 0.2, 1.0) * (kind === 'apartment' ? 0.7 : 1);
  const bseed = r();
  const glassy = kind === 'institution' && r() < 0.15;
  const stilt = kind === 'apartment' && r() < 0.7;
  const tileRoof = (kind === 'agraharam' || kind === 'oldhouse') && n === 4 && r() < 0.55;
  const balconyP = style.balconyChance[kind] ?? style.balconyChance.default;
  const acP = style.acChance[kind] ?? style.acChance.default;
  const chD = range(r, style.chajjaDepth[0], style.chajjaDepth[1]);
  const F = ctx.facade, G = ctx.generic;

  const cellQuad = (x0: number, z0: number, x1: number, z1: number, y0: number, y1: number, nrm: V3, cellKind: number, floor: number, col: V3, ws2 = ws) => {
    const w = Math.hypot(x1 - x0, z1 - z0);
    F.quad([x0, y0, z0], [x1, y0, z1], [x1, y1, z1], [x0, y1, z0], nrm,
      { color: col, fa: [r(), ws2, cellKind, weather], fb: [w, y1 - y0, floor, bseed] }, [[0, 0], [1, 0], [1, 1], [0, 1]]);
  };
  const facadeBox = (cx: number, cy: number, cz: number, hx: number, hy: number, hz: number, rot: number, col: V3, k = Cell.Plain) =>
    F.box(cx, cy, cz, hx, hy, hz, rot, { color: col, fa: [r(), 0, k, weather], fb: [hx * 2, hy * 2, 0, bseed] }, true);
  const gbox = (cx: number, cy: number, cz: number, hx: number, hy: number, hz: number, rot: number, col: V3, type: GM, rough = 0.8, em = 0) =>
    G.box(cx, cy, cz, hx, hy, hz, rot, { color: col, gm: [type, rough, em, r()] }, true);

  // ---------- walls ----------
  for (let i = 0; i < n; i++) {
    const [x0, z0] = P[i], [x1, z1] = P[(i + 1) % n];
    const dx = x1 - x0, dz = z1 - z0, L = Math.hypot(dx, dz);
    if (L < 0.3) continue;
    const tx = dx / L, tz = dz / L;
    const nx = tz, nz = -tx; const nrm: V3 = [nx, 0, nz];
    const rot = Math.atan2(nx, nz); // local +z = outward
    const front = (b.e[i] || 0) > 0;
    const at = (s: number): [number, number] => [x0 + tx * s, z0 + tz * s];
    // ----- ground floor -----
    if (commercial && front && L > 2.4) {
      const ns = Math.max(1, Math.round(L / range(r, style.shopW[0], style.shopW[1])));
      const sw = L / ns;
      for (let j = 0; j < ns; j++) {
        const [ax, az] = at(j * sw), [bx, bz] = at((j + 1) * sw);
        cellQuad(ax, az, bx, bz, 0, gh, nrm, Cell.Shop, 0, paint);
        if (!ctx.detail) continue;
        const mx = (ax + bx) / 2, mz = (az + bz) / 2;
        const shopSeed = Math.floor(r() * 1e9);
        const trade = pickW(mulberry(shopSeed), ctx.trades.map((t) => t.w));
        // signboard (Tamil + English, unique per shop)
        const signTop = gh - 0.08, signBot = gh - range(r, 0.85, 1.1);
        let cell = -1;
        if (ctx.signs.length < ctx.maxSigns) {
          cell = ctx.signs.length;
          ctx.signs.push({ cell, kind: r() < 0.6 ? 'flex' : 'paint', seed: shopSeed, trade, road: b.r?.[i] ?? -1 });
          const [u0, v0, u1, v1] = signUV(cell);
          const off = 0.1, hw = sw / 2 - 0.06;
          // viewer's right (looking at the wall) is -t, so the sign's left edge sits at +t
          const sx0 = mx + tx * hw + nx * off, sz0 = mz + tz * hw + nz * off, sx1 = mx - tx * hw + nx * off, sz1 = mz - tz * hw + nz * off;
          ctx.sign.quad([sx0, signBot, sz0], [sx1, signBot, sz1], [sx1, signTop, sz1], [sx0, signTop, sz0], nrm, { sg: [r() < 0.35 ? 1 : 0, 0, 0, 0] },
            [[u0, v1], [u1, v1], [u1, v0], [u0, v0]]);
          gbox(mx + nx * 0.05, (signTop + signBot) / 2, mz + nz * 0.05, hw + 0.03, (signTop - signBot) / 2 + 0.03, 0.045, rot, [0.08, 0.08, 0.08], GM.Metal, 0.5);
        }
        ctx.shops.push({ x: mx, z: mz, nx, nz, w: sw, trade, seed: shopSeed, sign: cell });
        // rolling-shutter housing
        gbox(mx + nx * 0.12, signBot - 0.17, mz + nz * 0.12, sw / 2 - 0.08, 0.15, 0.12, rot, [0.32, 0.33, 0.34], GM.Metal, 0.6);
        // tube light under the sign
        gbox(mx + nx * 0.3, signBot - 0.36, mz + nz * 0.3, Math.min(0.6, sw / 2 - 0.3), 0.025, 0.025, rot, [0.9, 0.95, 1], GM.Emissive, 0.3, 1);
        ctx.lights.push(mx + nx * 0.6, signBot - 0.4, mz + nz * 0.6, 0);
        // plinth step (shops sit 0.3–0.45 m above the road)
        const ph = range(r, 0.25, 0.45);
        gbox(mx + nx * 0.4, ph / 2, mz + nz * 0.4, sw / 2, ph / 2, 0.4, rot, mix3(hexToLin('#8f8a80'), paint, 0.15), GM.Granite, 0.7);
        // awning: sloped tin / tarpaulin
        if (r() < style.awningChance) {
          const ac = hexToLin(pick(r, style.awningColors));
          const depth = range(r, 0.9, 1.6), y0 = signBot - 0.05, y1 = y0 - range(r, 0.35, 0.6);
          const hw2 = sw / 2 - 0.02;
          const a0: V3 = [mx - tx * hw2, y0, mz - tz * hw2], a1: V3 = [mx + tx * hw2, y0, mz + tz * hw2];
          const b1: V3 = [a1[0] + nx * depth, y1, a1[2] + nz * depth], b0: V3 = [a0[0] + nx * depth, y1, a0[2] + nz * depth];
          const slopeN: V3 = [nx * 0.35, 0.94, nz * 0.35];
          const t = r() < 0.5 ? GM.Tin : GM.Tarp;
          G.quad(a0, a1, b1, b0, slopeN, { color: ac, gm: [t, 0.6, 0, r()] }, [[0, 0], [sw, 0], [sw, depth], [0, depth]]);
          G.quad(a0, b0, b1, a1, [-slopeN[0], -slopeN[1], -slopeN[2]], { color: mix3(ac, [0, 0, 0], 0.3), gm: [t, 0.6, 0, r()] }, [[0, 0], [sw, 0], [sw, depth], [0, depth]]);
        }
      }
    } else {
      const nb = Math.max(1, Math.round(L / range(r, style.bayW[0], style.bayW[1])));
      const bw = L / nb;
      const doorBay = front ? Math.floor(r() * nb) : -1;
      for (let j = 0; j < nb; j++) {
        const [ax, az] = at(j * bw), [bx, bz] = at((j + 1) * bw);
        let k: number = Cell.Window;
        if (sacred) k = Cell.Plain;
        else if (stilt) k = Cell.Stilt;
        else if (j === doorBay) k = Cell.Door;
        else if (!front && r() < 0.45) k = r() < 0.3 ? Cell.Vent : Cell.Plain;
        if (glassy) k = Cell.Glass;
        cellQuad(ax, az, bx, bz, 0, gh, nrm, k, 0, paint);
        if (ctx.detail && (k === Cell.Window || k === Cell.Door) && bw > 1.4) addChajja(ax, az, bx, bz, k === Cell.Door ? 2.25 : 2.3, gh);
      }
    }
    // ----- upper floors -----
    const nb = Math.max(1, Math.round(L / range(r, style.bayW[0], style.bayW[1])));
    const bw = L / nb;
    for (let f = 1; f < levels; f++) {
      const y0 = gh + (f - 1) * fh, y1 = y0 + fh;
      for (let j = 0; j < nb; j++) {
        const [ax, az] = at(j * bw), [bx, bz] = at((j + 1) * bw);
        let k: number = Cell.Window;
        if (sacred) k = Cell.Plain;
        else if (glassy) k = Cell.Glass;
        else if (ws === 5) k = Cell.Glass;
        else if (front && r() < balconyP && bw > 2.2) k = Cell.Balcony;
        else if (!front && r() < 0.45) k = r() < 0.35 ? Cell.Vent : Cell.Plain;
        cellQuad(ax, az, bx, bz, y0, y1, nrm, k, f, paint);
        if (!ctx.detail || bw < 1.4) continue;
        const mx = (ax + bx) / 2, mz = (az + bz) / 2;
        if (k === Cell.Window || k === Cell.Balcony) addChajja(ax, az, bx, bz, y0 + (k === Cell.Balcony ? 2.35 : 2.3) - 0.0, fh);
        if (k === Cell.Balcony) {
          const d = range(r, 0.9, 1.2), hw = bw / 2 - 0.15;
          facadeBox(mx + nx * d / 2, y0 + 0.06, mz + nz * d / 2, hw, 0.08, d / 2, rot, mix3(paint, [1, 1, 1], 0.1));
          facadeBox(mx + nx * (d - 0.05), y0 + 0.55, mz + nz * (d - 0.05), hw, 0.45, 0.06, rot, r() < 0.4 ? accent : paint);
          for (const s of [-1, 1]) facadeBox(mx + nx * d / 2 + tx * s * hw, y0 + 0.55, mz + nz * d / 2 + tz * s * hw, 0.06, 0.45, d / 2, rot, paint);
        }
        if (k === Cell.Window && r() < acP) {
          const side = r() < 0.5 ? -1 : 1, off = Math.min(bw / 2 - 0.45, 0.95) * side;
          gbox(mx + tx * off + nx * 0.16, y0 + 0.55, mz + tz * off + nz * 0.16, 0.4, 0.27, 0.14, rot, hexToLin(r() < 0.8 ? '#e9e7e1' : '#c9c6bd'), GM.Metal, 0.5);
        }
      }
    }
    // ----- parapet (flat roofs) -----
    if (!tileRoof && !sacred) {
      const ph = range(r, 0.9, 1.1), th = 0.14;
      const ix = -nx * th, iz = -nz * th;
      cellQuad(x0, z0, x1, z1, H, H + ph, nrm, Cell.Plain, levels, paint);
      cellQuad(x1 + ix, z1 + iz, x0 + ix, z0 + iz, H, H + ph, [-nx, 0, -nz], Cell.Plain, levels, mix3(paint, [0.5, 0.5, 0.5], 0.25));
      F.quad([x0, H + ph, z0], [x1, H + ph, z1], [x1 + ix, H + ph, z1 + iz], [x0 + ix, H + ph, z0 + iz], [0, 1, 0],
        { color: r() < 0.35 ? accent : paint, fa: [r(), 0, Cell.Trim, weather], fb: [L, th, levels, bseed] });
    }
    // ----- drain pipes at corners of front faces -----
    if (ctx.detail && front && L > 4 && levels > 1 && r() < 0.6) {
      const [px, pz] = at(range(r, 0.3, 0.8));
      gbox(px + nx * 0.07, H / 2, pz + nz * 0.07, 0.055, H / 2, 0.055, rot, hexToLin(pick(r, ['#8e8e88', '#6b6b66', '#a8a29a', '#2c2c2c'])), GM.Plain, 0.5);
    }

    function addChajja(ax: number, az: number, bx: number, bz: number, yTop: number, _cellH: number) {
      const mx = (ax + bx) / 2, mz = (az + bz) / 2, cw = Math.min(Math.hypot(bx - ax, bz - az) - 0.2, 1.9);
      facadeBox(mx + nx * chD / 2, yTop + 0.05, mz + nz * chD / 2, cw / 2, 0.05, chD / 2, rot, mix3(paint, [0.4, 0.4, 0.4], 0.12));
    }
  }

  // ---------- roof ----------
  const contour = P.map(([x, z]) => new Vector2(x, z));
  let tris: number[][] = [];
  try { tris = ShapeUtils.triangulateShape(contour, []); } catch { tris = []; }
  const flat = tris.flat();
  if (tileRoof) {
    // gable along the long axis
    const e0 = Math.hypot(P[1][0] - P[0][0], P[1][1] - P[0][1]), e1 = Math.hypot(P[2][0] - P[1][0], P[2][1] - P[1][1]);
    const s = e0 >= e1 ? 0 : 1; // long edges are s and s+2
    const A = P[s], B = P[(s + 1) % 4], C = P[(s + 2) % 4], D = P[(s + 3) % 4];
    const ridgeH = Math.min(e0, e1) / 2 * Math.tan(0.42);
    const m1: V3 = [(A[0] + D[0]) / 2, H + ridgeH, (A[1] + D[1]) / 2], m2: V3 = [(B[0] + C[0]) / 2, H + ridgeH, (B[1] + C[1]) / 2];
    const tile = jitter(hexToLin(style.tileRoof), r, 0.12);
    const ov = 0.35;
    const ext = (p: [number, number], q: V3): V3 => { const vx = p[0] - q[0], vz = p[1] - q[2], l = Math.hypot(vx, vz) || 1; return [p[0] + vx / l * ov, H - ov * Math.tan(0.42), p[1] + vz / l * ov]; };
    const a = ext(A, m1), bb = ext(B, m2), c = ext(C, m2), d = ext(D, m1);
    const slope = (p0: V3, p1: V3, p2: V3, p3: V3) => {
      const ux = p1[0] - p0[0], uy = p1[1] - p0[1], uz = p1[2] - p0[2], vx = p3[0] - p0[0], vy = p3[1] - p0[1], vz = p3[2] - p0[2];
      let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx; const l = Math.hypot(nx, ny, nz) || 1; nx /= l; ny /= l; nz /= l;
      if (ny < 0) { nx = -nx; ny = -ny; nz = -nz; }
      const len = Math.hypot(ux, uz);
      G.quad(p0, p1, p2, p3, [nx, ny, nz], { color: tile, gm: [GM.Tile, 0.85, 0, r()] }, [[0, 0], [len, 0], [len, 3], [0, 3]]);
    };
    slope(a, bb, m2, m1); slope(c, d, m1, m2);
    // gable triangles
    for (const [p, q, m] of [[A, D, m1], [C, B, m2]] as const) {
      const vx = q[0] - p[0], vz = q[1] - p[1], l = Math.hypot(vx, vz) || 1;
      const gn: V3 = [vz / l, 0, -vx / l];
      F.quad([p[0], H, p[1]], [q[0], H, q[1]], m, m, gn, { color: paint, fa: [r(), 0, Cell.Plain, weather], fb: [l, ridgeH, levels, bseed] });
    }
  } else if (flat.length) {
    G.polygon(b.f, flat, H + 0.02, true, { color: mix3(paint, hexToLin('#8a8478'), 0.65), gm: [GM.Concrete, 0.95, 0, r()] });
  }

  // ---------- roof clutter ----------
  if (ctx.detail && !tileRoof && !sacred && flat.length) {
    const cx = P.reduce((a, p) => a + p[0], 0) / n, cz = P.reduce((a, p) => a + p[1], 0) / n;
    const inside = (f: number): [number, number] => { const v = P[Math.floor(r() * n)]; return [v[0] + (cx - v[0]) * f, v[1] + (cz - v[1]) * f]; };
    if (r() < style.mumtyChance && levels >= 2) {
      const [mx, mz] = inside(range(r, 0.3, 0.45));
      const rot = Math.atan2(P[1][0] - P[0][0], P[1][1] - P[0][1]);
      facadeBox(mx, H + 1.25, mz, 1.3, 1.25, 1.15, rot, paint);
      gbox(mx, H + 2.55, mz, 1.45, 0.06, 1.3, rot, mix3(paint, [0.3, 0.3, 0.3], 0.3), GM.Concrete);
    }
    if (r() < style.tankChance) {
      const nt = 1 + pickW(r, [55, 30, 15]);
      const [tx0, tz0] = inside(range(r, 0.25, 0.4));
      const stand = range(r, 0.3, 1.4);
      const tr = range(r, 0.55, 0.75), th = range(r, 1.1, 1.6);
      for (let t = 0; t < nt; t++) {
        const ox = tx0 + t * (tr * 2 + 0.15), oz = tz0;
        if (stand > 0.5) gbox(ox, H + stand / 2, oz, tr + 0.05, stand / 2, tr + 0.05, 0, mix3(paint, [0.4, 0.4, 0.4], 0.4), GM.Concrete);
        G.cylinder(ox, H + stand, oz, tr, th, 10, { color: hexToLin(r() < 0.85 ? '#1d1d1d' : '#2f4f8f'), gm: [GM.Tank, 0.55, 0, r()] });
      }
    }
    if (r() < style.dishChance) {
      const [dx, dz] = inside(range(r, 0.15, 0.3));
      gbox(dx, H + 1.0, dz, 0.03, 0.45, 0.03, 0, [0.6, 0.6, 0.6], GM.Metal);
      gbox(dx + 0.15, H + 1.35, dz, 0.04, 0.32, 0.32, 0.6, [0.85, 0.85, 0.83], GM.Metal, 0.4);
    }
  }
  ctx.colliders.push({ f: b.f, h: H + (tileRoof ? 1.5 : 1) });
}
