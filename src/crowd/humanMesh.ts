// Procedural low-poly human bodies for the mid/far crowd tiers.
// Each vertex carries `part` (what colour slot it uses) and `limb` (which pivot animates it).
// Animation happens on the GPU (see crowdRenderer.ts), so 10k+ people cost one draw call per variant.
import * as THREE from 'three/webgpu';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export const enum Part { Top = 0, Skin = 1, Sleeve = 2, Lower = 3, Feet = 4, Hair = 5, Accent = 6, Drape = 7 }
export const enum Limb { None = 0, LegL = 1, LegR = 2, ArmL = 3, ArmR = 4, Head = 5 }

export type Variant = 'man_pants' | 'man_veshti' | 'woman_saree' | 'woman_churidar' | 'child' | 'man_lungi';
export const VARIANTS: Variant[] = ['man_pants', 'man_veshti', 'woman_saree', 'woman_churidar', 'child', 'man_lungi'];

// Anatomical pivots for a 1.0-scale adult (≈1.65 m). Scaled per-instance on the GPU.
export const HIP_Y = 0.9, SHOULDER_Y = 1.38, NECK_Y = 1.45;

function tag(g: THREE.BufferGeometry, part: Part, limb: Limb): THREE.BufferGeometry {
  g = g.index ? g.toNonIndexed() : g;
  const n = g.getAttribute('position').count;
  const pl = new Float32Array(n * 2); for (let i = 0; i < n; i++) { pl[i * 2] = part; pl[i * 2 + 1] = limb; }
  g.setAttribute('pl', new THREE.Float32BufferAttribute(pl, 2));
  g.deleteAttribute('uv');
  return g;
}
let Q = 1; // LOD quality multiplier for segment counts
function cyl(rt: number, rb: number, h: number, seg = 7, y = 0, x = 0, z = 0, sx = 1, sz = 1) {
  const g = new THREE.CylinderGeometry(rt, rb, h, Math.max(3, Math.round(seg * Q)), 1, Q < 1);
  g.scale(sx, 1, sz); g.translate(x, y + h / 2, z); return g;
}
function sph(r: number, y: number, x = 0, z = 0, sx = 1, sy = 1, sz = 1, ws = 8, hs = 6) {
  const g = new THREE.SphereGeometry(r, Math.max(4, Math.round(ws * Q)), Math.max(2, Math.round(hs * Q))); g.scale(sx, sy, sz); g.translate(x, y, z); return g;
}

function arms(out: THREE.BufferGeometry[], sleeveLen: number, female: boolean) {
  for (const s of [-1, 1]) {
    const limb = s < 0 ? Limb.ArmL : Limb.ArmR;
    const x = s * (female ? 0.19 : 0.215);
    // upper arm: sleeve part + bare part
    const upper = 0.3, fore = 0.28;
    const sl = Math.min(upper, sleeveLen);
    if (sl > 0) out.push(tag(cyl(0.05, 0.045, sl, 6, SHOULDER_Y - sl, x), Part.Sleeve, limb));
    if (upper - sl > 0) out.push(tag(cyl(0.042, 0.04, upper - sl, 6, SHOULDER_Y - upper, x), Part.Skin, limb));
    const foreSl = Math.max(0, sleeveLen - upper);
    if (foreSl > 0) out.push(tag(cyl(0.042, 0.036, foreSl, 6, SHOULDER_Y - upper - foreSl, x), Part.Sleeve, limb));
    out.push(tag(cyl(0.038, 0.032, fore - foreSl, 6, SHOULDER_Y - upper - fore, x), Part.Skin, limb));
    out.push(tag(sph(0.042, SHOULDER_Y - upper - fore - 0.04, x, 0, 0.8, 1.3, 0.6, 6, 4), Part.Skin, limb)); // hand
  }
}
function head(out: THREE.BufferGeometry[], female: boolean, child: boolean) {
  const hy = NECK_Y + 0.13;
  out.push(tag(cyl(0.045, 0.05, 0.08, 6, NECK_Y - 0.02), Part.Skin, Limb.Head));
  out.push(tag(sph(0.1, hy, 0, 0.005, 0.85, 1.12, 0.95, 9, 7), Part.Skin, Limb.Head));
  out.push(tag(sph(0.018, hy - 0.01, 0, 0.095, 1, 1.2, 1, 4, 3), Part.Skin, Limb.Head)); // nose
  // hair cap
  out.push(tag(sph(0.104, hy + 0.025, 0, -0.012, 0.88, 0.92, 0.98, 9, 5), Part.Hair, Limb.Head));
  if (female && !child) {
    out.push(tag(sph(0.06, hy - 0.02, 0, -0.11, 1, 0.9, 0.8, 6, 5), Part.Hair, Limb.Head)); // bun / plait root
    out.push(tag(cyl(0.03, 0.022, 0.35, 5, hy - 0.4, 0, -0.1), Part.Hair, Limb.Head)); // plait
    out.push(tag(sph(0.035, hy + 0.0, 0.05, -0.1, 1.2, 0.6, 0.8, 5, 4), Part.Accent, Limb.Head)); // jasmine (malli poo)
  }
}

function build(v: Variant): THREE.BufferGeometry {
  if (Q < 0.5) return buildFar(v);
  const out: THREE.BufferGeometry[] = [];
  const female = v === 'woman_saree' || v === 'woman_churidar';
  const child = v === 'child';
  // torso (shirt / blouse / kurta top)
  const shoulderW = female ? 0.36 : 0.42;
  out.push(tag(cyl(shoulderW / 2, female ? 0.16 : 0.17, SHOULDER_Y - HIP_Y + 0.02, 8, HIP_Y - 0.02, 0, 0, 1, 0.6), Part.Top, Limb.None));
  out.push(tag(sph(shoulderW / 2, SHOULDER_Y - 0.02, 0, 0, 1, 0.35, 0.62, 8, 4), Part.Top, Limb.None));
  if (female) out.push(tag(sph(0.075, 1.22, 0, 0.06, 1.9, 0.75, 0.8, 7, 5), Part.Top, Limb.None));
  head(out, female, child);
  // feet
  for (const s of [-1, 1]) out.push(tag(sph(0.05, 0.03, s * 0.09, 0.05, 0.9, 0.5, 2.0, 6, 4), Part.Feet, s < 0 ? Limb.LegL : Limb.LegR));

  switch (v) {
    case 'man_pants': case 'child': {
      for (const s of [-1, 1]) {
        const limb = s < 0 ? Limb.LegL : Limb.LegR;
        out.push(tag(cyl(0.082, 0.058, child ? 0.45 : HIP_Y - 0.06, 7, child ? HIP_Y - 0.45 : 0.06, s * 0.09), Part.Lower, limb));
        if (child) out.push(tag(cyl(0.05, 0.045, HIP_Y - 0.51, 6, 0.06, s * 0.09), Part.Skin, limb));
      }
      out.push(tag(cyl(0.175, 0.18, 0.12, 8, HIP_Y - 0.08, 0, 0, 1, 0.62), Part.Lower, Limb.None)); // seat/belt
      arms(out, child ? 0.14 : 0.18, false);
      break;
    }
    case 'man_veshti': case 'man_lungi': {
      // veshti / lungi: wrapped cloth tube from waist to ankle (lungi folded up shorter sometimes)
      out.push(tag(cyl(0.18, 0.2, HIP_Y - 0.05, 9, 0.07, 0, 0, 1, 0.75), Part.Lower, Limb.None));
      for (const s of [-1, 1]) out.push(tag(cyl(0.045, 0.04, 0.12, 6, 0.0, s * 0.09), Part.Skin, s < 0 ? Limb.LegL : Limb.LegR));
      // towel over shoulder (thundu)
      out.push(tag(new THREE.BoxGeometry(0.1, 0.5, 0.2).translate(-0.17, SHOULDER_Y - 0.2, 0), Part.Accent, Limb.None));
      arms(out, v === 'man_veshti' ? 0.18 : 0.0, false);
      break;
    }
    case 'woman_saree': {
      out.push(tag(cyl(0.17, 0.25, HIP_Y - 0.03, 10, 0.04, 0, 0, 1, 0.8), Part.Lower, Limb.None)); // pleated skirt drape
      // pallu: diagonal drape across chest, over the left shoulder, down the back
      const pallu = new THREE.BoxGeometry(0.2, 0.62, 0.3);
      pallu.rotateZ(0.5); pallu.translate(-0.02, 1.15, 0.0);
      out.push(tag(pallu, Part.Drape, Limb.None));
      out.push(tag(new THREE.BoxGeometry(0.16, 0.7, 0.04).translate(-0.12, 1.0, -0.13), Part.Drape, Limb.None));
      for (const s of [-1, 1]) out.push(tag(cyl(0.04, 0.035, 0.06, 6, 0.0, s * 0.08), Part.Skin, s < 0 ? Limb.LegL : Limb.LegR));
      arms(out, 0.1, true);
      break;
    }
    case 'woman_churidar': {
      out.push(tag(cyl(0.17, 0.23, 0.5, 9, HIP_Y - 0.42, 0, 0, 1, 0.72), Part.Top, Limb.None)); // kurta skirt
      for (const s of [-1, 1]) out.push(tag(cyl(0.07, 0.045, HIP_Y - 0.36, 7, 0.06, s * 0.085), Part.Lower, s < 0 ? Limb.LegL : Limb.LegR));
      const dupatta = new THREE.BoxGeometry(0.5, 0.08, 0.26); dupatta.translate(0, SHOULDER_Y - 0.05, 0.03);
      out.push(tag(dupatta, Part.Drape, Limb.None));
      arms(out, 0.3, true);
      break;
    }
  }
  const g = mergeGeometries(out, false)!;
  g.computeBoundingSphere();
  return g;
}

// Far LOD: a handful of boxes, still walk-animated (≈60 triangles).
function buildFar(v: Variant): THREE.BufferGeometry {
  const out: THREE.BufferGeometry[] = [];
  const female = v === 'woman_saree' || v === 'woman_churidar';
  const box = (w: number, h: number, d: number, y: number, x = 0) => new THREE.BoxGeometry(w, h, d).translate(x, y + h / 2, 0);
  out.push(tag(box(female ? 0.34 : 0.4, SHOULDER_Y - HIP_Y + 0.05, 0.22, HIP_Y - 0.03), Part.Top, Limb.None));
  out.push(tag(box(0.17, 0.24, 0.19, NECK_Y - 0.02), Part.Skin, Limb.Head));
  out.push(tag(box(0.18, 0.08, 0.2, NECK_Y + 0.16), Part.Hair, Limb.Head));
  if (v === 'man_pants' || v === 'child' || v === 'woman_churidar') {
    for (const s of [-1, 1]) out.push(tag(box(0.13, HIP_Y, 0.15, 0, s * 0.085), Part.Lower, s < 0 ? Limb.LegL : Limb.LegR));
  } else out.push(tag(box(female ? 0.42 : 0.36, HIP_Y, 0.3, 0), Part.Lower, Limb.None));
  for (const s of [-1, 1]) out.push(tag(box(0.08, 0.56, 0.09, SHOULDER_Y - 0.58, s * (female ? 0.2 : 0.23)), Part.Skin, s < 0 ? Limb.ArmL : Limb.ArmR));
  if (v === 'woman_saree') out.push(tag(box(0.12, 0.6, 0.26, 0.9, -0.1).rotateZ(0.0), Part.Drape, Limb.None));
  const g = mergeGeometries(out, false)!; g.computeBoundingSphere(); return g;
}

export type Lod = 0 | 1 | 2;
const cache = new Map<string, THREE.BufferGeometry>();
/** lod 0: near (~900 tris), 1: mid (~350), 2: far boxes (~60) */
export function humanGeometry(v: Variant, lod: Lod = 0): THREE.BufferGeometry {
  const k = v + lod;
  if (!cache.has(k)) { Q = lod === 0 ? 1.4 : lod === 1 ? 0.75 : 0.3; cache.set(k, build(v)); Q = 1; }
  return cache.get(k)!;
}
