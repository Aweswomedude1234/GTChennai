// GPU crowd renderer: one InstancedMesh per (variant, LOD). Limb animation, head wobble,
// raised-hand gestures and cloth patterns are all evaluated in TSL on the GPU.
import * as THREE from 'three/webgpu';
import {
  attribute, positionLocal, vec4, positionGeometry, time, sin, cos, abs, select, float, vec3, mix, step, fract, Fn, max,
} from 'three/tsl';
import { humanGeometry, VARIANTS, type Variant, type Lod, HIP_Y, SHOULDER_Y, NECK_Y } from './humanMesh';
import type { Appearance } from './appearance';

const LODS: Lod[] = [0, 1, 2];
export const LOD_DIST = [30, 90]; // metres: <30 near, <90 mid, else far

function makeMaterial(): THREE.MeshStandardNodeMaterial {
  const m = new THREE.MeshStandardNodeMaterial({ roughness: 0.82, metalness: 0 });
  const pl = attribute<'vec2'>('pl', 'vec2');
  const part = pl.x, limb = pl.y;
  // Per-instance block (28 floats, interleaved): see INSTANCE_LAYOUT
  const iA = attribute<'vec4'>('iA', 'vec4'), iB = attribute<'vec4'>('iB', 'vec4'), iC = attribute<'vec4'>('iC', 'vec4');
  const iD = attribute<'vec4'>('iD', 'vec4'), iE = attribute<'vec4'>('iE', 'vec4'), iF = attribute<'vec4'>('iF', 'vec4'), iG = attribute<'vec4'>('iG', 'vec4');
  const anim = iA; // phase, gait, pattern, topPattern
  const misc = vec4(iB.x, iB.y, iB.z, 0); // wobble, gesture, cadence
  const iH = attribute<'vec4'>('iH', 'vec4'); // heading, scale
  // NOTE: three applies positionNode AFTER instancing, so positionLocal is already in instance
  // space. We animate the raw geometry and add the rotated delta.
  m.positionNode = Fn(() => {
    const p = positionGeometry;
    const cyc = time.mul(misc.z).add(anim.x);
    const s = sin(cyc);
    const gait = anim.y;
    const legA = s.mul(0.42).mul(gait);
    const armA = s.mul(-0.32).mul(gait).add(gait.oneMinus().mul(sin(cyc.mul(0.3)).mul(0.04)));
    const raise = misc.y.mul(-2.3); // right arm raised forward (crossing-the-road hand)
    const ang = select(limb.equal(1), legA, select(limb.equal(2), legA.negate(),
      select(limb.equal(3), armA, select(limb.equal(4), mix(armA.negate(), raise, misc.y), float(0)))));
    const pivotY = select(limb.lessThan(2.5), float(HIP_Y), float(SHOULDER_Y));
    const dy = p.y.sub(pivotY);
    const c = cos(ang), sn = sin(ang);
    const y1 = pivotY.add(dy.mul(c)).sub(p.z.mul(sn));
    const z1 = dy.mul(sn).add(p.z.mul(c));
    // head wobble: roll around the neck (z axis)
    const wob = select(limb.equal(5), sin(time.mul(7.0).add(anim.x.mul(3.0))).mul(misc.x), float(0));
    const hy = y1.sub(NECK_Y);
    const x2 = p.x.mul(cos(wob)).sub(hy.mul(sin(wob)));
    const y2 = float(NECK_Y).add(p.x.mul(sin(wob))).add(hy.mul(cos(wob)));
    // vertical bob while walking, breathing while idle
    const bob = abs(s).mul(0.028).mul(gait).add(sin(time.mul(1.7).add(anim.x)).mul(0.004).mul(gait.oneMinus()).mul(p.y.div(1.6)));
    const d = vec3(x2, y2.add(bob), z1).sub(p).mul(iH.y);
    const ch = cos(iH.x), sh = sin(iH.x);
    return positionLocal.add(vec3(d.x.mul(ch).add(d.z.mul(sh)), d.y, d.x.negate().mul(sh).add(d.z.mul(ch))));
  })();

  const top = vec3(iB.w, iC.x, iC.y), lower = vec3(iC.z, iC.w, iD.x), skin = vec3(iD.y, iD.z, iD.w);
  const hair = vec3(iE.x, iE.y, iE.z), border = vec3(iE.w, iF.x, iF.y), accent = vec3(iF.z, iF.w, iG.x);
  const drape = vec3(iG.y, iG.z, iG.w);
  const pg = positionGeometry;
  const checks = abs(step(0.5, fract(pg.x.mul(9))).sub(step(0.5, fract(pg.y.mul(9)))));
  const stripes = step(0.55, fract(pg.x.mul(26)));
  const pat = anim.z, tpat = anim.w;
  const lowerC = mix(
    mix(lower, mix(lower, border, 0.55), checks.mul(select(pat.equal(1), float(1), float(0)))),
    border,
    select(pat.equal(2), step(pg.y, 0.2).mul(step(0.06, pg.y)), float(0)),
  );
  const topC = mix(mix(top, top.mul(0.55), checks.mul(select(tpat.equal(1), float(0.6), float(0)))), top.mul(0.7), stripes.mul(select(tpat.equal(3), float(0.6), float(0))));
  const drapeC = mix(drape, border, step(0.3, abs(pg.y.sub(1.0))).mul(select(pat.equal(2), float(1), float(0))));
  const feet = mix(skin, vec3(0.03, 0.022, 0.016), 0.65);
  m.colorNode = select(part.equal(0), topC, select(part.equal(1), skin, select(part.equal(2), topC,
    select(part.equal(3), lowerC, select(part.equal(4), feet, select(part.equal(5), hair, select(part.equal(6), accent, drapeC)))))));
  m.roughnessNode = select(part.equal(5), float(0.55), select(part.equal(1), float(0.6), float(0.85)));
  void max;
  return m;
}

const STRIDE = 32;
const NAMES = ['iA', 'iB', 'iC', 'iD', 'iE', 'iF', 'iG', 'iH'];
interface Bucket { mesh: THREE.InstancedMesh; buf: THREE.InstancedInterleavedBuffer; count: number }

export interface Person {
  id: number; app: Appearance; x: number; y: number; z: number; heading: number;
  gait: number; phase: number; wobble: number; gesture: number; cadence: number; visible: boolean;
}

/**
 * Holds every rendered person and redistributes them into LOD buckets each frame.
 * The simulation owns `people`; call `sync(camera)` once per frame after moving them.
 */
export class CrowdRenderer {
  readonly group = new THREE.Group();
  readonly people: Person[] = [];
  private buckets = new Map<string, Bucket>();
  private shadowMesh: THREE.InstancedMesh;
  private tmp = new THREE.Matrix4();
  stats = { near: 0, mid: 0, far: 0, culled: 0 };
  private frustum = new THREE.Frustum();
  private pm = new THREE.Matrix4();

  constructor(private capacity: number) {
    const mat = makeMaterial();
    for (const v of VARIANTS) for (const lod of LODS) {
      const cap = Math.ceil(capacity * (lod === 0 ? 0.12 : lod === 1 ? 0.35 : 0.6) * (v === 'man_pants' || v === 'woman_saree' ? 0.6 : 0.4));
      const geo = humanGeometry(v, lod).clone();
      // one interleaved instance buffer: WebGPU allows only 8 vertex buffers per pipeline
      const buf = new THREE.InstancedInterleavedBuffer(new Float32Array(cap * STRIDE), STRIDE, 1);
      buf.setUsage(THREE.DynamicDrawUsage);
      NAMES.forEach((name, k) => geo.setAttribute(name, new THREE.InterleavedBufferAttribute(buf, 4, k * 4)));
      const mesh = new THREE.InstancedMesh(geo, mat, cap);
      mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      mesh.frustumCulled = false; mesh.count = 0;
      mesh.castShadow = lod === 0; mesh.receiveShadow = lod < 2;
      this.group.add(mesh);
      this.buckets.set(v + lod, { mesh, buf, count: 0 });
    }
    // contact shadows (blob under every visible person) — cheap and grounds the crowd
    const sg = new THREE.CircleGeometry(0.42, 10).rotateX(-Math.PI / 2).translate(0, 0.025, 0);
    const smat = new THREE.MeshBasicNodeMaterial({ transparent: true, depthWrite: false, color: 0x000000 });
    const uvn = positionGeometry.xz.length().div(0.42);
    smat.opacityNode = float(0.38).mul(float(1).sub(uvn.mul(uvn)));
    this.shadowMesh = new THREE.InstancedMesh(sg, smat, capacity);
    this.shadowMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.shadowMesh.frustumCulled = false; this.shadowMesh.count = 0; this.shadowMesh.renderOrder = 1;
    this.group.add(this.shadowMesh);
  }

  add(app: Appearance, x: number, z: number, heading = 0): Person {
    const p: Person = { id: this.people.length, app, x, y: 0, z, heading, gait: 1, phase: Math.random() * 6.28, wobble: 0, gesture: 0, cadence: 5.4 + Math.random() * 0.8, visible: true };
    this.people.push(p);
    return p;
  }
  remove(p: Person) { const i = this.people.indexOf(p); if (i >= 0) { this.people[i] = this.people[this.people.length - 1]; this.people.pop(); } }
  clear() { this.people.length = 0; }

  sync(camera: THREE.Camera, maxDist = 400) {
    for (const b of this.buckets.values()) b.count = 0;
    let sc = 0;
    this.pm.multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
    this.frustum.setFromProjectionMatrix(this.pm);
    const cx = camera.position.x, cz = camera.position.z;
    const st = this.stats; st.near = st.mid = st.far = st.culled = 0;
    const sphere = new THREE.Sphere(new THREE.Vector3(), 1.2);
    const m = this.tmp.elements;
    for (const p of this.people) {
      if (!p.visible) continue;
      const dx = p.x - cx, dz = p.z - cz, d = Math.sqrt(dx * dx + dz * dz);
      if (d > maxDist) { st.culled++; continue; }
      sphere.center.set(p.x, p.y + 0.9, p.z);
      if (!this.frustum.intersectsSphere(sphere)) { st.culled++; continue; }
      const lod: Lod = d < LOD_DIST[0] ? 0 : d < LOD_DIST[1] ? 1 : 2;
      if (lod === 0) st.near++; else if (lod === 1) st.mid++; else st.far++;
      const b = this.buckets.get(p.app.variant + lod)!;
      if (b.count >= b.mesh.instanceMatrix.count) continue;
      const i = b.count++;
      const s = p.app.scale, c = Math.cos(p.heading) * s, sn = Math.sin(p.heading) * s;
      // rotation about Y so local +z faces heading direction (heading 0 → +z)
      m[0] = c; m[1] = 0; m[2] = -sn; m[3] = 0; m[4] = 0; m[5] = s; m[6] = 0; m[7] = 0;
      m[8] = sn; m[9] = 0; m[10] = c; m[11] = 0; m[12] = p.x; m[13] = p.y; m[14] = p.z; m[15] = 1;
      b.mesh.instanceMatrix.array.set(m, i * 16);
      if (sc < this.shadowMesh.instanceMatrix.count && d < 120) this.shadowMesh.instanceMatrix.array.set(m, (sc++) * 16);
      const B = b.buf.array as Float32Array, o = i * STRIDE, a = p.app;
      B[o] = p.phase; B[o + 1] = p.gait; B[o + 2] = a.pattern; B[o + 3] = a.topPattern;
      B[o + 4] = p.wobble; B[o + 5] = p.gesture; B[o + 6] = p.cadence * a.gait;
      B.set(a.top, o + 7); B.set(a.lower, o + 10); B.set(a.skin, o + 13); B.set(a.hair, o + 16);
      B.set(a.border, o + 19); B.set(a.accent, o + 22); B.set(a.drape, o + 25);
      B[o + 28] = p.heading; B[o + 29] = p.app.scale;
    }
    for (const b of this.buckets.values()) {
      b.mesh.count = b.count;
      if (b.count) {
        b.mesh.instanceMatrix.clearUpdateRanges(); b.mesh.instanceMatrix.addUpdateRange(0, b.count * 16); b.mesh.instanceMatrix.needsUpdate = true;
        b.buf.clearUpdateRanges(); b.buf.addUpdateRange(0, b.count * STRIDE); b.buf.needsUpdate = true;
      }
    }
    this.shadowMesh.count = sc;
    this.shadowMesh.instanceMatrix.clearUpdateRanges(); this.shadowMesh.instanceMatrix.addUpdateRange(0, sc * 16);
    this.shadowMesh.instanceMatrix.needsUpdate = true;
  }
}
