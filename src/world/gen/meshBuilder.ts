// Minimal worker-safe mesh builder. Each builder has a fixed attribute layout so the main
// thread can turn the transferred arrays straight into BufferGeometry.

export type V3 = [number, number, number];
export interface AttrSpec { name: string; size: number }

export class MeshBuilder {
  readonly data: Record<string, number[]> = {};
  readonly index: number[] = [];
  vcount = 0;
  constructor(readonly spec: AttrSpec[]) { for (const s of spec) this.data[s.name] = []; }

  /** push one vertex; `attrs` must provide every attribute in spec order except position/normal handled by caller */
  vert(attrs: Record<string, ArrayLike<number>>): number {
    for (const s of this.spec) {
      const v = attrs[s.name]; const d = this.data[s.name];
      for (let i = 0; i < s.size; i++) d.push(v ? v[i] ?? 0 : 0);
    }
    return this.vcount++;
  }

  /**
   * Quad a-b-c-d (any winding). `n` is the intended outward normal; winding is fixed to face it.
   * `per` are shared attributes; `uvs` optional 4 uv pairs.
   */
  quad(a: V3, b: V3, c: V3, d: V3, n: V3, per: Record<string, ArrayLike<number>>, uvs?: [number, number][]) {
    const e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const gx = e1[1] * e2[2] - e1[2] * e2[1], gy = e1[2] * e2[0] - e1[0] * e2[2], gz = e1[0] * e2[1] - e1[1] * e2[0];
    const flip = gx * n[0] + gy * n[1] + gz * n[2] < 0;
    const P = [a, b, c, d];
    const base = this.vcount;
    for (let i = 0; i < 4; i++) this.vert({ ...per, position: P[i], normal: n, uv: uvs ? uvs[i] : per.uv ?? [0, 0] });
    if (!flip) this.index.push(base, base + 1, base + 2, base, base + 2, base + 3);
    else this.index.push(base, base + 2, base + 1, base, base + 3, base + 2);
  }

  /** axis-aligned-in-local-frame box: origin o, axes ax (length/2 scaled), up y, depth along nz */
  box(cx: number, cy: number, cz: number, hx: number, hy: number, hz: number, rot: number, per: Record<string, ArrayLike<number>>, skipBottom = true, uvScale = 1) {
    const c = Math.cos(rot), s = Math.sin(rot);
    const T = (x: number, y: number, z: number): V3 => [cx + x * c + z * s, cy + y, cz - x * s + z * c];
    const N = (x: number, y: number, z: number): V3 => [x * c + z * s, y, -x * s + z * c];
    const v = [T(-hx, -hy, -hz), T(hx, -hy, -hz), T(hx, hy, -hz), T(-hx, hy, -hz), T(-hx, -hy, hz), T(hx, -hy, hz), T(hx, hy, hz), T(-hx, hy, hz)];
    const u = uvScale;
    const uvX: [number, number][] = [[0, 0], [hx * 2 * u, 0], [hx * 2 * u, hy * 2 * u], [0, hy * 2 * u]];
    const uvZ: [number, number][] = [[0, 0], [hz * 2 * u, 0], [hz * 2 * u, hy * 2 * u], [0, hy * 2 * u]];
    const uvY: [number, number][] = [[0, 0], [hx * 2 * u, 0], [hx * 2 * u, hz * 2 * u], [0, hz * 2 * u]];
    this.quad(v[4], v[5], v[6], v[7], N(0, 0, 1), per, uvX);   // +z
    this.quad(v[1], v[0], v[3], v[2], N(0, 0, -1), per, uvX);  // -z
    this.quad(v[5], v[1], v[2], v[6], N(1, 0, 0), per, uvZ);   // +x
    this.quad(v[0], v[4], v[7], v[3], N(-1, 0, 0), per, uvZ);  // -x
    this.quad(v[3], v[7], v[6], v[2], N(0, 1, 0), per, uvY);   // top
    if (!skipBottom) this.quad(v[0], v[1], v[5], v[4], N(0, -1, 0), per, uvY);
  }

  /** vertical cylinder (open bottom) */
  cylinder(cx: number, y0: number, cz: number, r: number, h: number, seg: number, per: Record<string, ArrayLike<number>>, cap = true) {
    const base = this.vcount;
    for (let i = 0; i <= seg; i++) {
      const a = (i / seg) * Math.PI * 2, x = Math.cos(a), z = Math.sin(a);
      this.vert({ ...per, position: [cx + x * r, y0, cz + z * r], normal: [x, 0, z], uv: [i / seg * 2 * Math.PI * r, 0] });
      this.vert({ ...per, position: [cx + x * r, y0 + h, cz + z * r], normal: [x, 0, z], uv: [i / seg * 2 * Math.PI * r, h] });
    }
    for (let i = 0; i < seg; i++) { const a = base + i * 2; this.index.push(a, a + 1, a + 3, a, a + 3, a + 2); }
    if (cap) {
      const c = this.vert({ ...per, position: [cx, y0 + h + r * 0.15, cz], normal: [0, 1, 0], uv: [0, 0] });
      const first = this.vcount;
      for (let i = 0; i <= seg; i++) { const a = (i / seg) * Math.PI * 2; this.vert({ ...per, position: [cx + Math.cos(a) * r, y0 + h, cz + Math.sin(a) * r], normal: [Math.cos(a) * 0.3, 0.95, Math.sin(a) * 0.3], uv: [Math.cos(a), Math.sin(a)] }); }
      for (let i = 0; i < seg; i++) this.index.push(c, first + i + 1, first + i);
    }
  }

  /** flat polygon (pre-triangulated indices into pts) at height y, facing up or down */
  polygon(pts: number[], tris: number[], y: number, up: boolean, per: Record<string, ArrayLike<number>>) {
    const base = this.vcount;
    for (let i = 0; i < pts.length / 2; i++) this.vert({ ...per, position: [pts[i * 2], y, pts[i * 2 + 1]], normal: [0, up ? 1 : -1, 0], uv: [pts[i * 2], pts[i * 2 + 1]] });
    for (let i = 0; i < tris.length; i += 3) {
      if (up) this.index.push(base + tris[i], base + tris[i + 2], base + tris[i + 1]);
      else this.index.push(base + tris[i], base + tris[i + 1], base + tris[i + 2]);
    }
  }

  /** export as transferable typed arrays */
  build(): { attrs: Record<string, Float32Array>; index: Uint32Array; count: number } {
    const attrs: Record<string, Float32Array> = {};
    for (const s of this.spec) attrs[s.name] = new Float32Array(this.data[s.name]);
    return { attrs, index: new Uint32Array(this.index), count: this.vcount };
  }
}

export const FACADE_SPEC: AttrSpec[] = [
  { name: 'position', size: 3 }, { name: 'normal', size: 3 }, { name: 'color', size: 3 }, { name: 'uv', size: 2 }, { name: 'fa', size: 4 }, { name: 'fb', size: 4 },
];
export const GENERIC_SPEC: AttrSpec[] = [
  { name: 'position', size: 3 }, { name: 'normal', size: 3 }, { name: 'color', size: 3 }, { name: 'uv', size: 2 }, { name: 'gm', size: 4 },
];
export const SIGN_SPEC: AttrSpec[] = [
  { name: 'position', size: 3 }, { name: 'normal', size: 3 }, { name: 'uv', size: 2 }, { name: 'sg', size: 4 },
];

/** generic material types (gm.x) — interpreted in materials.ts */
export const enum GM { Plain = 0, Tin = 1, Tarp = 2, Tank = 3, Tile = 4, Concrete = 5, Metal = 6, Glass = 7, Emissive = 8, Cloth = 9, Granite = 10, Sand = 11, Wood = 12, Stucco = 13 }

export function hexToLin(h: string): V3 {
  const n = parseInt(h.slice(1), 16);
  const l = (c: number) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return [l((n >> 16) & 255), l((n >> 8) & 255), l(n & 255)];
}
