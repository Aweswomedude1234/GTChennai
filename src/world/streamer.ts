// Chunk streaming: two LOD rings (detail near, simplified far), built in Web Workers.
// Near chunks get full detail (signs, chajjas, roof clutter), shadows and physics colliders.
import * as THREE from 'three/webgpu';
import { toGeometry, type RegionMeta } from './region';
import { facadeMaterial, genericMaterial, signMaterial } from './materials';
import type { Physics } from '../physics/physics';
import type { ShopInfo } from './gen/buildings';

type Built = { attrs: Record<string, Float32Array>; index: Uint32Array; count: number };
interface ChunkRec {
  key: string; cx: number; cz: number; centerX: number; centerZ: number;
  state: 'none' | 'far' | 'near'; pending: 'far' | 'near' | null;
  group: THREE.Group | null; signTex: THREE.Texture | null; signMat: THREE.Material | null;
  shops: ShopInfo[]; lights: number[];
}
export interface StreamStats { near: number; far: number; pending: number; built: number; lastBuildMs: number }

export class Streamer {
  readonly group = new THREE.Group();
  readonly chunks = new Map<string, ChunkRec>();
  private workers: Worker[] = [];
  private busy: boolean[] = [];
  private queue: { key: string; detail: boolean; prio: number }[] = [];
  private jobs = new Map<number, { key: string; detail: boolean; w: number; t0: number }>();
  private nextId = 1;
  readonly facadeMat = facadeMaterial();
  readonly genericMat = genericMaterial();
  nearR = 280; farR = 1150;
  stats: StreamStats = { near: 0, far: 0, pending: 0, built: 0, lastBuildMs: 0 };
  onChunkNear?: (rec: ChunkRec) => void;
  onChunkUnload?: (rec: ChunkRec) => void;

  constructor(private meta: RegionMeta, private base: string, private physics: Physics) {
    const cs = meta.chunkSize, [x0, z0] = meta.bounds;
    for (const key of meta.chunks) {
      const [cx, cz] = key.split('_').map(Number);
      this.chunks.set(key, { key, cx, cz, centerX: x0 + (cx + 0.5) * cs, centerZ: z0 + (cz + 0.5) * cs, state: 'none', pending: null, group: null, signTex: null, signMat: null, shops: [], lights: [] });
    }
  }

  async init(style: unknown, names: unknown, fonts: unknown[]) {
    const n = Math.max(1, Math.min(3, (navigator.hardwareConcurrency || 4) - 2));
    const roadNames = this.meta.roads.map((r) => r.name);
    for (let i = 0; i < n; i++) {
      const w = new Worker(new URL('./chunkWorker.ts', import.meta.url), { type: 'module' });
      w.onmessage = (e) => this.onMessage(i, e.data);
      w.onerror = (e) => console.error('chunk worker error', e.message);
      w.postMessage({ type: 'init', base: location.href, style, names, roadNames, fonts });
      this.workers.push(w); this.busy.push(false);
    }
  }

  /** call each frame with the focus position (player / camera) */
  update(fx: number, fz: number) {
    const want: { key: string; detail: boolean; prio: number }[] = [];
    for (const c of this.chunks.values()) {
      const d = Math.hypot(c.centerX - fx, c.centerZ - fz) - this.meta.chunkSize * 0.5;
      const target = d < this.nearR ? 'near' : d < this.farR ? 'far' : 'none';
      // hysteresis on the way out
      const keepNear = c.state === 'near' && d < this.nearR + 60;
      const keepFar = c.state !== 'none' && d < this.farR + 120;
      if (target === 'near' && c.state !== 'near' && c.pending !== 'near') want.push({ key: c.key, detail: true, prio: d });
      else if (target === 'far' && c.state === 'none' && !c.pending) want.push({ key: c.key, detail: false, prio: d + 400 });
      else if (target !== 'near' && c.state === 'near' && !keepNear && !c.pending) want.push({ key: c.key, detail: false, prio: d + 200 });
      else if (target === 'none' && c.state !== 'none' && !keepFar) this.unload(c);
    }
    for (const w of want) if (!this.queue.some((q) => q.key === w.key && q.detail === w.detail)) this.queue.push(w);
    // drop queued jobs that are no longer wanted, then sort by priority
    this.queue = this.queue.filter((q) => { const c = this.chunks.get(q.key)!; return q.detail ? c.state !== 'near' : c.state === 'none' || c.state === 'near'; });
    this.queue.sort((a, b) => a.prio - b.prio);
    for (let i = 0; i < this.workers.length; i++) {
      if (this.busy[i] || !this.queue.length) continue;
      const job = this.queue.shift()!;
      const c = this.chunks.get(job.key)!;
      c.pending = job.detail ? 'near' : 'far';
      const id = this.nextId++;
      this.jobs.set(id, { key: job.key, detail: job.detail, w: i, t0: performance.now() });
      this.busy[i] = true;
      this.workers[i].postMessage({ type: 'build', id, key: job.key, detail: job.detail, url: new URL(`${this.base}/chunks/${job.key}.json`, location.href).href });
    }
    let near = 0, far = 0; for (const c of this.chunks.values()) { if (c.state === 'near') near++; else if (c.state === 'far') far++; }
    this.stats.near = near; this.stats.far = far; this.stats.pending = this.queue.length + this.jobs.size;
  }

  private onMessage(wi: number, msg: { type: string; id: number; key: string; detail: boolean; out: Record<string, Built>; colliders: { f: number[]; h: number }[]; shops: ShopInfo[]; lights: number[]; atlas: ImageBitmap | null; error?: string }) {
    this.busy[wi] = false;
    const job = this.jobs.get(msg.id); this.jobs.delete(msg.id);
    const c = this.chunks.get(msg.key); if (!c) return;
    c.pending = null;
    if (msg.type === 'error') { console.error('chunk build failed', msg.key, msg.error); return; }
    if (job) this.stats.lastBuildMs = performance.now() - job.t0;
    this.stats.built++;
    this.disposeGroup(c);
    const g = new THREE.Group(); g.name = 'chunk_' + c.key;
    const add = (b: Built, mat: THREE.Material, shadow: boolean) => {
      if (!b.count) return;
      const m = new THREE.Mesh(toGeometry(b), mat);
      m.castShadow = shadow; m.receiveShadow = true; g.add(m);
    };
    add(msg.out.facade, this.facadeMat, msg.detail);
    add(msg.out.generic, this.genericMat, msg.detail);
    if (msg.atlas && msg.out.sign.count) {
      const tex = new THREE.Texture(msg.atlas);
      tex.flipY = false; tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 4; tex.generateMipmaps = true; tex.minFilter = THREE.LinearMipmapLinearFilter;
      tex.needsUpdate = true;
      c.signTex = tex; c.signMat = signMaterial(tex);
      add(msg.out.sign, c.signMat, false);
    }
    this.group.add(g); c.group = g;
    const wasNear = c.state === 'near';
    c.state = msg.detail ? 'near' : 'far';
    c.shops = msg.shops; c.lights = msg.lights;
    if (msg.detail) { this.physics.addChunk(c.key, msg.colliders); this.onChunkNear?.(c); }
    else if (wasNear) { this.physics.removeChunk(c.key); this.onChunkUnload?.(c); }
  }

  private disposeGroup(c: ChunkRec) {
    if (!c.group) return;
    this.group.remove(c.group);
    c.group.traverse((o) => { if ((o as THREE.Mesh).isMesh) (o as THREE.Mesh).geometry.dispose(); });
    c.signTex?.dispose(); c.signMat?.dispose(); c.signTex = null; c.signMat = null; c.group = null;
  }
  private unload(c: ChunkRec) {
    if (c.state === 'near') { this.physics.removeChunk(c.key); this.onChunkUnload?.(c); }
    this.disposeGroup(c); c.state = 'none';
  }
  /** true once every chunk within the near ring is built (used by loading screen / harness) */
  nearReady(fx: number, fz: number) {
    for (const c of this.chunks.values()) {
      const d = Math.hypot(c.centerX - fx, c.centerZ - fz) - this.meta.chunkSize * 0.5;
      if (d < this.nearR && c.state !== 'near') return false;
    }
    return true;
  }
}
